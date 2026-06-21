import Testing
@testable import TotalRecallCore

@Suite("VMRegionCategory Classification")
struct VMRegionTests {
    private let executableProtection: UInt32 = 0x05  // VM_PROT_READ | VM_PROT_EXECUTE
    private let writableProtection: UInt32   = 0x03  // VM_PROT_READ | VM_PROT_WRITE
    private let readOnlyProtection: UInt32   = 0x01  // VM_PROT_READ

    // MARK: - Heap (malloc user_tags 1–12)

    @Test("user_tag 1 (VM_MEMORY_MALLOC) → Heap")
    func mallocTag() {
        #expect(VMRegionCategory(userTag: 1, protection: writableProtection, hasFilePath: false) == .heap)
    }

    @Test("user_tag 7 (VM_MEMORY_MALLOC_TINY) → Heap")
    func mallocTinyTag() {
        #expect(VMRegionCategory(userTag: 7, protection: writableProtection, hasFilePath: false) == .heap)
    }

    @Test("user_tag 12 (VM_MEMORY_MALLOC_PROB_GUARD) → Heap")
    func mallocProbGuardTag() {
        #expect(VMRegionCategory(userTag: 12, protection: writableProtection, hasFilePath: false) == .heap)
    }

    // MARK: - Stack

    @Test("user_tag 30 (VM_MEMORY_STACK) → Stack")
    func stackTag() {
        #expect(VMRegionCategory(userTag: 30, protection: writableProtection, hasFilePath: false) == .stack)
    }

    // MARK: - __TEXT

    @Test("Executable protection without file → __TEXT")
    func executableNoFile() {
        #expect(VMRegionCategory(userTag: 0, protection: executableProtection, hasFilePath: false) == .text)
    }

    @Test("Executable protection with file → __TEXT (framework)")
    func executableWithFile() {
        #expect(VMRegionCategory(userTag: 0, protection: executableProtection, hasFilePath: true) == .text)
    }

    // MARK: - File-backed

    @Test("Non-executable with file path → File-backed")
    func fileBacked() {
        #expect(VMRegionCategory(userTag: 0, protection: readOnlyProtection, hasFilePath: true) == .fileBacked)
    }

    @Test("Writable with file path → File-backed")
    func writableFileBacked() {
        #expect(VMRegionCategory(userTag: 0, protection: writableProtection, hasFilePath: true) == .fileBacked)
    }

    // MARK: - Anonymous

    @Test("No tag, not executable, no file → Anonymous")
    func anonymous() {
        #expect(VMRegionCategory(userTag: 0, protection: writableProtection, hasFilePath: false) == .anonymous)
    }

    @Test("Unknown tag, not executable, no file → Anonymous")
    func unknownTagAnonymous() {
        #expect(VMRegionCategory(userTag: 99, protection: writableProtection, hasFilePath: false) == .anonymous)
    }

    // MARK: - VMRegion aggregation

    @Test("VMRegion id equals its category")
    func regionID() {
        let region = VMRegion(category: .heap, size: 1024, residentSize: 512)
        #expect(region.id == .heap)
    }

    @Test("VMRegion stores size and residentSize")
    func regionSizes() {
        let region = VMRegion(category: .stack, size: 8 * 1024 * 1024, residentSize: 1024 * 1024)
        #expect(region.size == 8 * 1024 * 1024)
        #expect(region.residentSize == 1024 * 1024)
    }
}
