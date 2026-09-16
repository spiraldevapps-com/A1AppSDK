# A1AppSDK 3.0 Architecture

How the SDK is put together and what each part does. Read this before changing the SDK. To add it to an app, see `Integration-Guide.md`.

## The idea

Every app used to repeat the same third-party setup in its own `AppDelegate`, in slightly different ways, and each copy drifted. The SDK now owns all of it.

Three rules shape everything else.

1. **All vendor setup lives in the package.** No app calls `FirebaseApp.configure()`, `Adapty.activate` or any other vendor bootstrap.
2. **The app supplies keys, nothing more.** One value, `A1Configuration`, carries them. Keys differ per app. What is done with them does not.
3. **No vendor type crosses the public boundary.** Apps see `A1SDK.shared` plus the `A1` protocols and models. Only `AdaptyAdapter` imports Adapty. Replacing a vendor means writing one new file, not touching every app.

## What is where

Everything is under `Sources/A1AppSDK`.

| Folder | What it holds |
|---|---|
| `Core/` | The facade `A1SDK`, the module contract, the app's settings, the shared user id. No vendor imports |
| `Core/Models/` | The plain value types apps see: events, placements, paywall shapes, purchase results, ad state |
| `Core/Protocols/` | The four things an app programs against: analytics, subscriptions, ads, support |
| `Analytics/` | The dispatcher that fans one event out to every vendor |
| `Analytics/Adapters/` | Firebase Analytics, AppMetrica, Meta, Clarity |
| `Monetization/` | Adapty, and the decoder for paywalls the app draws itself |
| `Advertising/` | AdMob and the consent gate |
| `Platform/Adapters/` | Firebase core, auth, remote config, messaging, performance, StoreKit, tracking, attribution, reachability, rating, app update |
| `Support/Adapters/` | Intercom |
| `Classes/` | The old 1.0.x code. Still compiled, still used by some adapters. See the last section |

## How a launch happens

The app calls two methods. Everything else follows from them.

```swift
A1SDK.shared.register(A1SDK.standardModules())
A1SDK.shared.configure(with: A1Configuration(...))
```

1. `register` builds all nineteen modules. It does not start anything.
2. `configure` sorts them by their declared phase and calls `configure(context:)` on each one, in order, on the main thread.
3. Each module gets a context holding the settings, the shared user id, and the analytics dispatcher.
4. Analytics vendors are attached to the dispatcher right after they start, so anything reported earlier in the launch is replayed into them.
5. After the last module, the SDK stops holding on to early events, logs the first-open event, and closes the launch trace.

A module registered later is started immediately instead of waiting.

### Phases

A phase is just a number. Lower runs first. The gaps let a module sit between two stages without renumbering anything.

| Phase | Number | For |
|---|---|---|
| `.bootstrap` | 50 | The one thing everything needs. Firebase core |
| | 51, 52 | Performance, then the two event vendors, so launch events are sent live |
| `.foundation` | 100 | Things that need the launch options or must exist before the user id |
| `.identity` | 200 | Establishing who the user is |
| `.remoteConfig` | 300 | Remote settings, so later phases can read flags |
| `.analytics` | 400 | Analytics vendors with no ordering constraint |
| `.monetization` | 500 | Subscriptions |
| | 590 | Consent, before ads |
| `.advertising` | 600 | Ads |
| `.support` | 700 | Customer messaging, rating prompt |
| `.notifications` | 800 | Push token |

The order is not decoration. Firebase must exist before anything logs an event. The user id must exist before vendors that segment by user. Consent must be settled before ads load.

## The modules

Nineteen, all optional. A module with no matching setting does nothing.

| Module | Starts at | What it does |
|---|---|---|
| `FirebaseCoreAdapter` | 50 | Calls `FirebaseApp.configure()`. Everything Firebase depends on it |
| `PerformanceAdapter` | 51 | Firebase Performance. Opens the launch trace and offers traces to the app |
| `FirebaseAnalyticsAdapter` | 52 | Sends events to Firebase and errors to Crashlytics |
| `AppMetricaAdapter` | 52 | Sends events and errors to AppMetrica |
| `MetaAdapter` | 100 | Meta app events. Holds them until the app forwards `didFinishLaunching` |
| `ReachabilityAdapter` | 100 | One network monitor for the process |
| `TrackingAdapter` | 100 | App Tracking Transparency status and prompt, and the advertising id |
| `AttributionAdapter` | 100 | Apple Search Ads attribution, fetched once per install. Off unless an app asks for it |
| `FirebaseAuthAdapter` | 200 | Anonymous sign-in, and publishes the user id |
| `StoreKitAdapter` | 200 | Apple's own view of entitlement, and the storefront country |
| `RemoteConfigAdapter` | 300 | Fetches and decodes Remote Config |
| `AppUpdateAdapter` | 301 | The force and optional update alerts |
| `ClarityAdapter` | 400 | Clarity session recording. Not an event vendor |
| `AdaptyAdapter` | 500 | Subscriptions, entitlement and paywalls |
| `ConsentAdapter` | 590 | The consent round trip, and the gate that holds ads back |
| `AdMobAdapter` | 600 | Ads, on top of the existing ad engine in `Classes` |
| `IntercomAdapter` | 700 | Intercom setup, login, attributes and push |
| `RatingAdapter` | 700 | The App Store review prompt and its pacing |
| `MessagingAdapter` | 800 | The push token hand-off to Firebase Messaging |

Each one follows the same shape: a plain `init`, a fixed phase, and all vendor work inside `configure(context:)`.

## How the parts talk to each other

Modules never call each other directly. They share five mechanisms.

### The user id

One object, `A1Identity`, holds the current id. Anyone can watch it.

On a first launch there is no id yet, and launch must not wait for a network call. So the id starts empty, which is a valid state. `FirebaseAuthAdapter` publishes Firebase's own session if there is one, otherwise the last id it saved, then signs in anonymously in the background and publishes the result.

Every vendor that carries a user id watches this one object, so each re-identifies itself. Before, each app did this by hand in several places and it was easy to miss one.

An app with a real login publishes its own id the same way and everything follows.

### Events

Every event goes through one dispatcher, which sends it to Firebase, AppMetrica and Meta.

Modules that start early have things worth reporting before any event vendor exists. So the dispatcher holds early calls and replays them into each vendor as it starts. After boot it stops holding and just delivers.

Renaming and shared parameters are applied when an event is delivered, not when it is logged, so even a call made before the SDK was configured gets them.

Event names live in two lists. `A1EventKey` holds the product events the apps already use, kept exactly as they were because every dashboard depends on them. `A1DiagnosticKey` holds the SDK's own health signals, all starting with `a1sdk_` so they can never be confused with an app's names.

### Subscription state

`AdaptyAdapter` owns one flag. It is saved to disk, so a paying user is not treated as free while the vendor answers, or for a whole offline session. On the first launch after adopting the SDK it is seeded from the app's own flag.

Only one function turns a vendor profile into that flag, and it only notifies when the value actually changes. Three things listen: the ad module turns ads off, Intercom updates its `is_pro` attribute, and the app updates whatever it shows.

### Paywalls

Paywalls designed in the Adapty dashboard come back as a ready view controller, which the SDK caches per placement. Placements with no design come back as JSON for the app to draw.

The rules that matter:

- A paywall already on screen is not presented again.
- If the screen that asked has gone away, the app is told, rather than a paywall appearing over something else.
- There is a load timeout. A late answer is dropped instead of interrupting the user.
- The dismiss callback fires exactly once per presentation, including when the app closed the paywall itself.
- A dashboard paywall records its own impression, so the SDK does not add a second one. A paywall the app draws is recorded with one explicit call.

### Consent and ads

Google's ad SDK starts loading as soon as it starts, so the gate exists to stop that happening before consent is settled.

The consent module asks the consent service at launch. It opens the gate when ads are allowed, or when the service could not answer at all, so a network failure never blocks ads forever. In a region that requires the form, the gate stays shut until the form has been answered, and opens again by itself afterwards.

The ad module re-applies its settings every time the gate opens. That is why ads start after the form with no app code, and why a subscription change can never be the thing that starts ads too early.

### Lifecycle

The app forwards four UIKit callbacks to `A1SDK.shared`, and the SDK passes each to the modules that asked for it, in phase order. Six modules use them: Meta, tracking, StoreKit, app update, Intercom and messaging.

### Launch traces

Two Firebase Performance traces come for free when performance monitoring is on.

`a1sdk_boot` covers the launch and carries one timing per module plus a total. `a1sdk_adapty_ready` covers the wait a user actually feels: it starts when Adapty is activated and ends when both the subscription answer and the prefetched paywalls have arrived.

## Rules when you change the SDK

**A module's `init` must do nothing.** All nineteen are built before any of them starts, which is before Firebase is configured. A vendor call in a stored property crashes the app on launch. This shipped once. Store plain values in `init` and resolve vendor objects inside `configure(context:)`.

**Every subscription hands back a token that cancels itself when released.** That makes leaks impossible, and it means a token nobody stores unsubscribes at once. Keep it in a property.

**Degrade, do not crash.** A module whose vendor is missing reports it through analytics and carries on. Apps register different subsets.

**Keep the SDK generic.** No app's event name, threshold, storage key or dashboard id belongs in the package. Anything that would only suit one app becomes a setting instead. This is the rule that matters most: one adapter tuned to one app becomes every other app's behaviour on their next upgrade.

**Empty ids at the start of a launch are intentional.** Do not add code that waits for one.

## The old `Classes` folder

This is the 1.0.x code. It is still compiled and still public so apps on the old API keep building. Some of it is the working engine behind a new module.

| Still working | Used by |
|---|---|
| The ad engine and its pacing rules | The ad module, which changed the shape of the API but not what it decides |
| The update alert and version comparison | The update module, which owns the wiring around it |
| The consent calls | The consent module |
| The shared Remote Config shapes | The ads and update modules |
| `EventManager` | Old call sites. It now forwards into the dispatcher, so nothing is counted twice |

Unused leftovers: the old Clarity, tracking and validation helpers, and the example debug screens.

Two overloads are marked deprecated, both the ones that took ad settings alongside the consent form. Ads now reconfigure themselves, so those settings were ignored anyway.
