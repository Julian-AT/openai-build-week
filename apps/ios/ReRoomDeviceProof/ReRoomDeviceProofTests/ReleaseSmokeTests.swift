import Testing

@Suite("Release test bundle smoke")
struct ReleaseSmokeTests {
    @Test("the Release test bundle has a loadable executable")
    func bundleLoads() {
        #expect(true)
    }
}
