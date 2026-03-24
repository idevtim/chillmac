import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: kHelperMachServiceName)
listener.delegate = delegate
listener.resume()

// Install signal handlers to clean up test mode on termination
signal(SIGTERM) { _ in
    HelperService.cleanupOnExit()
    exit(0)
}
signal(SIGINT) { _ in
    HelperService.cleanupOnExit()
    exit(0)
}

RunLoop.current.run()
