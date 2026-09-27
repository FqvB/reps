// The voice output seam: SystemSpeaker in the app, a fake in tests.
protocol Speaker: AnyObject {
    // Loads the voice and sets up audio so the first callout isn't late (§5.7 pre-warm).
    func prepare()
    // Speaks one line; calls `finished` once when it ends, unless stop() cancelled it first.
    func speak(_ text: String, finished: @escaping () -> Void)
    // Cuts off the current line; its `finished` is never called.
    func stop()
}
