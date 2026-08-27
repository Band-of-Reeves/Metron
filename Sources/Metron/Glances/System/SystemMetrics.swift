import Foundation
import Darwin

/// One reading of the machine.
struct SystemSnapshot: Equatable {
    var cpuTotal: Double = 0            // 0...1, busy share since the last sample
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var perCore: [Double] = []          // 0...1 per logical core

    var memoryUsed: Double = 0          // bytes
    var memoryTotal: Double = 0
    var memoryApp: Double = 0
    var memoryWired: Double = 0
    var memoryCompressed: Double = 0
    var memoryCached: Double = 0
    var swapUsed: Double = 0
    var swapTotal: Double = 0

    var netDown: Double = 0             // bytes/second
    var netUp: Double = 0
    var netDownTotal: Double = 0        // bytes since boot
    var netUpTotal: Double = 0

    var diskFree: Double = 0            // bytes
    var diskTotal: Double = 0

    var load1: Double = 0
    var uptime: TimeInterval = 0
    var coreCount: Int = 0

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? (diskTotal - diskFree) / diskTotal : 0 }
    var swapFraction: Double { swapTotal > 0 ? swapUsed / swapTotal : 0 }
}

/// Reads CPU, memory, network and disk straight from the kernel.
///
/// Rate figures (CPU busy share, network throughput) are differences between
/// consecutive samples, so the first reading after launch reports zero — there
/// is nothing yet to difference against. That is honest, and it settles on the
/// next tick.
final class SystemMetrics {

    private var previousCPU: [UInt32] = []
    private var previousNet: (rx: UInt64, tx: UInt64, at: Date)?

    func sample() -> SystemSnapshot {
        var s = SystemSnapshot()
        s.coreCount = ProcessInfo.processInfo.activeProcessorCount
        s.uptime = ProcessInfo.processInfo.systemUptime
        readCPU(into: &s)
        readMemory(into: &s)
        readSwap(into: &s)
        readNetwork(into: &s)
        readDisk(into: &s)
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { s.load1 = loads[0] }
        return s
    }

    // MARK: - CPU

    /// Per-core tick counters, differenced against the previous sample.
    private func readCPU(into s: inout SystemSnapshot) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var ticks = [UInt32](repeating: 0, count: Int(cpuCount) * states)
        for i in 0..<(Int(cpuCount) * states) {
            ticks[i] = UInt32(bitPattern: info[i])
        }

        defer { previousCPU = ticks }
        guard previousCPU.count == ticks.count else { return }

        var busySum = 0.0, totalSum = 0.0, userSum = 0.0, systemSum = 0.0
        var cores: [Double] = []
        cores.reserveCapacity(Int(cpuCount))

        for c in 0..<Int(cpuCount) {
            let base = c * states
            let d: (Int) -> Double = { state in
                // Tick counters are monotonic; a wrap shows up as a negative
                // delta, and reporting zero for one tick beats a spike.
                let now = ticks[base + state], before = self.previousCPU[base + state]
                return now >= before ? Double(now - before) : 0
            }
            let user = d(Int(CPU_STATE_USER))
            let sys  = d(Int(CPU_STATE_SYSTEM))
            let nice = d(Int(CPU_STATE_NICE))
            let idle = d(Int(CPU_STATE_IDLE))
            let busy = user + sys + nice
            let total = busy + idle
            cores.append(total > 0 ? busy / total : 0)
            busySum += busy; totalSum += total
            userSum += user + nice; systemSum += sys
        }

        guard totalSum > 0 else { return }
        s.cpuTotal = busySum / totalSum
        s.cpuUser = userSum / totalSum
        s.cpuSystem = systemSum / totalSum
        s.perCore = cores
    }

    // MARK: - Memory

    private func readMemory(into s: inout SystemSnapshot) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let page = Double(vm_kernel_page_size)
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        let cached = Double(stats.external_page_count) * page
        // Activity Monitor's "App Memory": anonymous pages the system cannot
        // simply throw away, less the ones apps have marked reclaimable.
        let app = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page

        s.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        s.memoryApp = app
        s.memoryWired = wired
        s.memoryCompressed = compressed
        s.memoryCached = cached
        // "Memory Used" = app + wired + compressed. File-backed pages are
        // cache, not pressure, so they are deliberately left out.
        s.memoryUsed = app + wired + compressed
    }

    private func readSwap(into s: inout SystemSnapshot) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }
        s.swapUsed = Double(usage.xsu_used)
        s.swapTotal = Double(usage.xsu_total)
    }

    // MARK: - Network

    /// Interface byte counters from `NET_RT_IFLIST2`, which reports 64-bit
    /// totals. `getifaddrs` only carries 32-bit counters, which wrap every
    /// 4 GB — often enough on a fast link to invent throughput spikes.
    private func readNetwork(into s: inout SystemSnapshot) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = base.advanced(by: offset)
                    .assumingMemoryBound(to: if_msghdr.self).pointee
                let msgLen = Int(hdr.ifm_msglen)
                guard msgLen > 0 else { break }
                if hdr.ifm_type == RTM_IFINFO2 {
                    let m2 = base.advanced(by: offset)
                        .assumingMemoryBound(to: if_msghdr2.self).pointee
                    // Loopback traffic is not network traffic.
                    if m2.ifm_data.ifi_type != UInt8(IFT_LOOP) {
                        rx += m2.ifm_data.ifi_ibytes
                        tx += m2.ifm_data.ifi_obytes
                    }
                }
                offset += msgLen
            }
        }

        s.netDownTotal = Double(rx)
        s.netUpTotal = Double(tx)

        let now = Date()
        defer { previousNet = (rx, tx, now) }
        guard let prev = previousNet else { return }
        let elapsed = now.timeIntervalSince(prev.at)
        guard elapsed > 0.05 else { return }
        s.netDown = rx >= prev.rx ? Double(rx - prev.rx) / elapsed : 0
        s.netUp = tx >= prev.tx ? Double(tx - prev.tx) / elapsed : 0
    }

    // MARK: - Disk

    private func readDisk(into s: inout SystemSnapshot) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return }
        s.diskTotal = Double(values.volumeTotalCapacity ?? 0)
        // "Important usage" is what Finder reports as available: it counts
        // purgeable space the system would reclaim under pressure.
        s.diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
