import Foundation
import Testing

@testable import GamepadFeature

@Test func simultaneousSticksKeepIndependentOwnership() {
  let left = NSObject()
  let right = NSObject()
  let leftID = ObjectIdentifier(left)
  let rightID = ObjectIdentifier(right)
  var input = GamepadTouchState()
  let accepted1 = input.begin(leftID, on: .leftStick)
  #expect(accepted1)
  let accepted2 = input.begin(rightID, on: .rightStick)
  #expect(accepted2)
  input.move(leftID, displacement: SIMD2(60, 0), radius: 60)
  input.move(rightID, displacement: SIMD2(0, -60), radius: 60)
  input.end(leftID)
  #expect(input.leftStick == .zero)
  #expect(input.rightStick == SIMD2(0, -1))
  #expect(input.rightStickHeld)
}

@Test func anotherFingerCannotStealAPressedControl() {
  let first = NSObject()
  let second = NSObject()
  var input = GamepadTouchState()
  let accepted3 = input.begin(ObjectIdentifier(first), on: .button(.rightTrigger))
  #expect(accepted3)
  let accepted4 = input.begin(ObjectIdentifier(second), on: .button(.rightTrigger))
  #expect(!accepted4)
  input.end(ObjectIdentifier(second))
  #expect(input.buttons == [.rightTrigger])
  input.end(ObjectIdentifier(first))
  #expect(input.buttons.isEmpty)
}

@Test func buttonMovementCannotOverwriteTheRightStick() {
  let look = NSObject()
  let fire = NSObject()
  var input = GamepadTouchState()
  let accepted5 = input.begin(ObjectIdentifier(look), on: .rightStick)
  #expect(accepted5)
  let accepted6 = input.begin(ObjectIdentifier(fire), on: .button(.rightTrigger))
  #expect(accepted6)
  input.move(ObjectIdentifier(look), displacement: SIMD2(60, 0), radius: 60)
  input.move(ObjectIdentifier(fire), displacement: SIMD2(-60, 0), radius: 60)
  #expect(input.rightStick == SIMD2(1, 0))
  #expect(input.buttons == [.rightTrigger])
}

@Test func cancellationReleasesEveryOutput() {
  let left = NSObject()
  let right = NSObject()
  let fire = NSObject()
  var input = GamepadTouchState()
  let accepted7 = input.begin(ObjectIdentifier(left), on: .leftStick)
  #expect(accepted7)
  let accepted8 = input.begin(ObjectIdentifier(right), on: .rightStick)
  #expect(accepted8)
  let accepted9 = input.begin(ObjectIdentifier(fire), on: .button(.rightTrigger))
  #expect(accepted9)
  input.move(ObjectIdentifier(left), displacement: SIMD2(30, 30), radius: 60)
  input.move(ObjectIdentifier(right), displacement: SIMD2(-60, 0), radius: 60)
  input.reset()
  #expect(input.leftStick == .zero)
  #expect(input.rightStick == .zero)
  #expect(input.buttons.isEmpty)
  #expect(!input.leftStickHeld && !input.rightStickHeld)
  let accepted10 = input.begin(ObjectIdentifier(left), on: .rightStick)
  #expect(accepted10)
}

@Test func centerNoiseIsIgnoredAndDiagonalInputIsBounded() {
  let touch = NSObject()
  let identifier = ObjectIdentifier(touch)
  var input = GamepadTouchState()
  let accepted11 = input.begin(identifier, on: .leftStick)
  #expect(accepted11)
  input.move(identifier, displacement: SIMD2(3, 4), radius: 60)
  #expect(input.leftStick == .zero)
  input.move(identifier, displacement: SIMD2(120, 120), radius: 60)
  let length = (input.leftStick.x * input.leftStick.x + input.leftStick.y * input.leftStick.y)
    .squareRoot()
  #expect(abs(length - 1) < 0.0001)
}

@Test func sensitivityChangesSpeedWithoutExceedingAnAxisMagnitudeOfOne() {
  let touch = NSObject()
  var input = GamepadTouchState()
  let accepted12 = input.begin(ObjectIdentifier(touch), on: .rightStick)
  #expect(accepted12)
  input.move(ObjectIdentifier(touch), displacement: SIMD2(30, 30), radius: 60)
  let slow = input.rightStick(sensitivity: 0.25)
  let fast = input.rightStick(sensitivity: 4)
  #expect(abs(slow.x) < abs(fast.x))
  #expect(abs((fast.x * fast.x + fast.y * fast.y).squareRoot() - 1) < 0.0001)
}
