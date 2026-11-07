# ⚡ Power of AI Agents

> Native iOS & macOS app that shows, in real time, why small local AI models can outpace cloud APIs, and how a swarm of parallel agents builds an interface layer by layer. Built with SwiftUI.

[Report Bug](https://github.com/VidiPT89/PowerOfAIAgents/issues) · [Request Feature](https://github.com/VidiPT89/PowerOfAIAgents/issues)

## ✨ Features

- ✅ **Agent race:** four robotic spider agents crawl the same article and decide, link by link, whether each link is about spiders. Two run locally, two in the cloud. They all walk at the same speed, so the only difference is how long each one needs to decide
- ✅ Live verdict boxes on the page: green for correct finds, red for false alarms, dashed for missed links
- ✅ Cloud agents show the request travelling to the data centre and back (TCP · TLS, server queue, inference, response)
- ✅ Live scoreboard with finds, decisions and average latency per decision, plus a final "× more decisions" summary
- ✅ **Agent swarm:** from 1 to 32 cursors take layers from a shared queue and build a review dashboard on a canvas, with size badges and a live "agents · layers" status pill
- ✅ Exact expected build time and speed-up compared with a single agent (the swarm is deterministic, so the result is known before it starts)
- ✅ **Latency anatomy:** stacked bars showing where every millisecond goes (TCP, TLS, routing, queue, inference) for each agent
- ✅ **Cascade simulator:** choose how much traffic a local model escalates to the cloud and see the resulting average latency
- ✅ Deterministic, seedable simulation engine, separated from the UI and covered by unit tests run on every push (GitHub Actions)
- ✅ Privacy manifest included: no tracking, no data collected, no network access
- ✅ Animated splash screen with credits
- ✅ Runtime language switch: Português (PT-PT) and English
- ✅ Dark mode, Light mode and System mode
- ✅ Custom colour identity inspired by [ividi.dev](https://ividi.dev/): orange, burnt amber and near-black
- ✅ One shared SwiftUI codebase for iPhone, iPad and Mac

> **Note:** this is an illustrative simulation. The agent names (Ember, Nimbus, Stratus, Flint) are fictional, and the latencies use realistic orders of magnitude for on-device inference, network round trips, TLS, server queues and token-by-token generation. No real model or network call is involved.

## 🛠️ Tech Stack

| Category | Technology |
|----------|------------|
| Language | Swift 6 |
| UI | SwiftUI, Canvas (iOS 17+ / macOS 14+) |
| Text layout | Core Text |
| Testing | XCTest |
| Project | XcodeGen |

## 🚀 Quick Start

**Prerequisites**
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (only needed to regenerate the project)
- iOS 17+ simulator or device, or a Mac running macOS 14+

**Steps**

1. Clone the repository

```bash
git clone https://github.com/VidiPT89/PowerOfAIAgents.git
cd PowerOfAIAgents
```

2. (Optional) Regenerate the Xcode project

```bash
xcodegen generate
```

3. Open the project and run

```bash
open PowerOfAIAgents.xcodeproj
```

Choose the `PowerOfAIAgents` scheme for iPhone/iPad or `PowerOfAIAgents-macOS` for the Mac.

## 📖 Usage

- **Race:** press **Start race** (or Space on the Mac). Pick a duration of 10, 20, 30 or 60 seconds. **Reset** starts a new run with a fresh seed.
- **Swarm:** choose the number of agents with the slider and press **Build**. Compare the elapsed time with the single-agent time.
- **Why:** read the latency breakdown and drag the cascade slider to see how escalating only low-confidence cases changes the average latency.
- **Settings:** switch language (PT/EN), appearance (System, Light, Dark) and whether the intro is shown on launch.

## 🧪 Testing

```bash
xcodebuild -project PowerOfAIAgents.xcodeproj -scheme PowerOfAIAgents-macOS -destination 'platform=macOS' test
xcodebuild -project PowerOfAIAgents.xcodeproj -scheme PowerOfAIAgents -destination 'generic/platform=iOS Simulator' build
```

The unit tests cover the race engine (determinism regardless of frame rate, verdict counters, local versus cloud throughput), the cascade maths, the swarm engine (every layer built exactly once, more agents finishing faster, prediction equal to a frame-by-frame run), the article parser and text layout (every link placed, punctuation kept next to its link) and the parity of links between the Portuguese and English articles. The same checks run on GitHub Actions for every push.

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

## 👨‍💻 Author

**David Arsénio Martins**

🌐 Website: [ividi.dev](https://ividi.dev/)
🐙 GitHub: [@VidiPT89](https://github.com/VidiPT89/)

## 🤝 Contributing

Contributions, issues and feature requests are welcome. Feel free to check the [issues page](https://github.com/VidiPT89/PowerOfAIAgents/issues).

---

<p align="center">Developed by <a href="https://ividi.dev">David Arsénio Martins</a></p>
<p align="center">If you like this project, consider giving it a ⭐</p>
