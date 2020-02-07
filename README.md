# cocoapods-rome

![](yolo.jpg)

Rome makes it easy to build a list of frameworks for consumption outside of
Xcode, e.g. for a Swift script.

This is a fork of Rome that specifically build xcframework for iOS/Catalyst.

## Installation

Add following to your gem file:

```bash
gem 'cocoapods-rome', github: "siuying/Rome", branch: "gn_master"
```

## Important

In the examples below the target 'caesar' could either be an existing target of a project managed by cocapods for which you'd like to run a swift script **or** it could be fictitious, for example if you wish to run this on a standalone Podfile and get the frameworks you need for adding to your xcode project manually.

## Usage 

Write a simple Podfile, like this:

### iOS 

#### Make a dynamic xcframework

```ruby
platform :ios, '12.0'

use_frameworks!

plugin 'cocoapods-rome', { dsym: false, configuration: 'Release' }

target 'caesar' do
  pod 'Alamofire'
end
```

then run this:

```bash
pod install
```

and you will end up with xcframeworks:

```
$ tree Rome/
Rome/
└── Alamofire.xcframework
```

#### Make a static xcframework


```ruby
platform :ios, '12.0'

plugin 'cocoapods-rome', { dsym: false, configuration: 'Release' }

target 'caesar' do
  pod 'Alamofire'
end
```

## Advanced Usage


For your production builds, when you want dSYMs created and stored:

```ruby
platform :ios, '12.0'

plugin 'cocoapods-rome', {
  dsym: true,
  configuration: 'Release'
}

target 'caesar' do
  pod 'Alamofire'
end
```

Resulting in:

```
$ tree dSYM/
dSYM/
├── iphoneos
│   └── Alamofire.framework.dSYM
│       └── Contents
│           ├── Info.plist
│           └── Resources
│               └── DWARF
│                   └── Alamofire
└── iphonesimulator
│   └── Alamofire.framework.dSYM
│       └── Contents
│           ├── Info.plist
│           └── Resources
│               └── DWARF
│                   └── Alamofire
└── maccatalyst
    └── Alamofire.framework.dSYM
        └── Contents
            ├── Info.plist
            └── Resources
                └── DWARF
                    └── Alamofire
```

## Hooks

The plugin allows you to provides hooks that will be called during the installation process.

### `pre_compile`

This hook allows you to make any last changes to the generated Xcode project before the compilation of frameworks begins.

It receives the `Pod::Installer` as its only argument.

### `post_compile`

This hook allows you to run code after the compilation of the frameworks finished and they have been moved to the `Rome` folder.

It receives the `Pod::Installer` as its only argument.
