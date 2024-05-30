# LiveInstance

A Swift Library for retrieving a list of living instances of a class.

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/p-x9/swift-live-instance)](https://github.com/p-x9/swift-live-instance/issues)
[![Github forks](https://img.shields.io/github/forks/p-x9/swift-live-instance)](https://github.com/p-x9/swift-live-instance/network/members)
[![Github stars](https://img.shields.io/github/stars/p-x9/swift-live-instance)](https://github.com/p-x9/swift-live-instance/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/p-x9/swift-live-instance)](https://github.com/p-x9/swift-live-instance/)

## Usage

```swift
//　Get a list of instances of `UIView` by weak reference.
let weakRefs = liveInstances(for: UIView.self)

/// list of views
let views = weakRefs.objects
```
