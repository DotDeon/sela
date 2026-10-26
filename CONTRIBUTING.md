# Contributing to Sela

Thanks for helping. Every change reaches `main` through a pull request.

## How a change gets in

1. Fork the repo and create a branch from `main`.
2. Make your change, and keep it to one thing per pull request.
3. Open a pull request against `main` and say what it fixes and how you tested it.
4. A review bot reads the pull request and leaves comments. It never approves anything.
5. A maintainer reviews it. Nothing merges until a maintainer approves it.

If your pull request runs GitHub Actions, they wait until a maintainer lets them run.

## Building the app

Sela needs macOS 15 or later and Xcode. Open `app/Sela.xcodeproj` and run the `Sela` scheme.
It signs ad hoc by default, so it runs on the Mac that built it.
To sign with your own Apple team, copy `app/Support/Signing.local.xcconfig.example` to `app/Support/Signing.local.xcconfig` and fill it in.

## Reporting a problem

Open an issue at https://github.com/DotDeon/sela/issues with what you did, what you expected, and what happened.

## Licence

Sela is under the GNU GPL, version 3. By sending a pull request you agree your change is released under the same licence.
