import QtQuick

// Island side of Capture: deliberately empty. Opening it makes the island
// blur->fade its content out at the CURRENT size (Island.captureFrom); the
// emptied background is then handed to CaptureScope (Island.stealForCapture),
// which owns the overlay, the flying square and the actions.
Item {
    signal closeRequested
}
