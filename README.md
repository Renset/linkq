<div align="center">
<img width="256" alt="256@2x" src="https://github.com/Renset/linkq/assets/364877/8fe64119-8b98-4b2d-8ceb-c3e6331e44c3">

</div>

# linkq
<img alt="GitHub top language" src="https://img.shields.io/github/languages/top/Renset/linkq"> <img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/Renset/linkq"> <img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/Renset/linkq/xcode.yml"> <img alt="GitHub all releases" src="https://img.shields.io/github/downloads/Renset/linkq/total"> 

Dead simple macOS menu bar utility for monitoring connection quality.

- ICMP/TCP probes
- Good/Average/Poor/Offline status
- 5-minute menu graph and longer history in settings
- Optional macOS Wi-Fi tweak for lower latency spikes

You can download the latest signed universal binary on the [Releases](https://github.com/Renset/linkq/releases) page.

## Screenshot

<img width="320" alt="linkq menu screenshot" src="Screenshot.png">

## Probe limitations
ICMP mode requires ICMP packets to be allowed by your network. Use TCP mode if ICMP is blocked.

## Motivation
I wanted a tiny menu bar indicator for network glitches during calls and games.

## Contribution
Contributions are welcome.

## Build
Open `linkq.xcodeproj` and build the `linkq` scheme.

## License
MIT. See [LICENSE](https://github.com/Renset/linkq/blob/main/LICENSE) for details.
