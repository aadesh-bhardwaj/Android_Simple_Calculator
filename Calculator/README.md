# Android CI with Harness (Build, Test, Publish to GCS)

This repository contains a **Harness CI** pipeline that:

1) clones the Android repo,  
2) **builds** a **Debug APK** using Gradle in a container with the Android SDK,  
3) **runs JUnit unit tests** and surfaces results in Harness,  
4) **uploads the APK to Google Cloud Storage (GCS)** under a run-scoped path.

> **CD/distribution** (Firebase/TestFlight) is intentionally **skipped** for this assignment.

---

## Table of Contents

- [Architecture](#architecture)  
- [Prerequisites](#prerequisites)  
- [Repository Layout](#repository-layout)  
- [One-Time Setup (Reproducible Steps)](#one-time-setup-reproducible-steps)  
- [Pipeline YAML](#pipeline-yaml)  
- [YAML Fields Explained](#yaml-fields-explained)  
- [How to Run](#how-to-run)  
- [What to Expect Per Step](#what-to-expect-per-step)  
- [Cleanup](#cleanup)

---

## Architecture

- **Runner:** Kubernetes (Harness **KubernetesDirect** on your cluster via a delegate)  
- **Build Image:** `stupidosaurus/android-sdk-gradle:latest` (JDK 17 + Gradle + Android SDK 30)  
- **Build:** `./gradlew clean assembleDebug`  
- **Unit Tests:** `./gradlew testDebugUnitTest` (JUnit XML parsed by Harness)  
- **Artifacts:** APK uploaded to **GCS** at `harness/test/<pipeline.sequenceId>/`  

---

## Prerequisites

- **Harness** account with a **Project** and **Org**.  
- **Connectors** in Harness:
  - **Codebase** `SimpleCalc` → your Git provider (GitHub/GitLab/Bitbucket).
  - **Kubernetes** `test101` → points to a cluster with a **Harness delegate** installed.
  - **Docker Registry** `stupido_saurus` (only if your image is private) → access to `stupidosaurus/android-sdk-gradle:latest`.
  - **GCS** `GCS_Connector` → Service Account with write access to bucket `atmosly-tfstate-atmosly-439606`.
- **Gradle/JUnit config** in your Android app (module `app`):
  ```gradle
  android {
    testOptions {
      unitTests {
        includeAndroidResources = true
        returnDefaultValues = true
      }
    }
  }
  dependencies {
    testImplementation 'junit:junit:4.13.2'
  }
  ```

> **Note on caching:** stage-level caching is enabled for `/harness/gradle/caches` and `/harness/gradle/wrapper`. For best results, set `GRADLE_USER_HOME=/harness/gradle` in your steps so Gradle writes to the cached location.

---

## Repository Layout

```
repo-root/
└─ Calculator/            # Android project directory (Gradle wrapper present)
   ├─ app/
   │  ├─ src/...
   │  └─ build.gradle
   ├─ gradlew             # executable
   ├─ gradle/
   └─ settings.gradle
```

> The pipeline `cd`s into `Calculator` before running Gradle commands.

---

## One-Time Setup (Reproducible Steps)

1) **Create connectors** (Harness → Project → Connectors)
- **Code**: `SimpleCalc` → point to your repository.
- **Kubernetes**: `test101` → install a **delegate** if not present.
- **Docker Registry**: `stupido_saurus` → only if the Docker image is private.
- **GCS**: `GCS_Connector` → supply a Service Account JSON with write access to the bucket.

2) **Add the pipeline** (Harness → CI → Pipelines → New)
- Paste the YAML below (or import from repo).

3) **(Optional) Create an auto-trigger**
- Triggers → **Git Push** → choose branches → attach this pipeline.

4) **Commit Gradle test settings** (see *Prerequisites* snippet) if not already in place.

---

## Pipeline YAML

```yaml
pipeline:
  name: SimpleCalc
  identifier: SimpleCalc
  projectIdentifier: default_project
  orgIdentifier: default
  properties:
    ci:
      codebase:
        connectorRef: SimpleCalc
        build: <+input>
        sparseCheckout: []
  stages:
    - stage:
        name: Build_Android
        identifier: Build_Android
        type: CI
        spec:
          cloneCodebase: true
          infrastructure:
            type: KubernetesDirect
            spec:
              connectorRef: test101
              namespace: imported
              automountServiceAccountToken: true
              nodeSelector: {}
              os: Linux
          execution:
            steps:
              - step:
                  type: Run
                  name: Build APK
                  identifier: Build_APK
                  spec:
                    connectorRef: stupido_saurus
                    image: stupidosaurus/android-sdk-gradle:latest
                    shell: Sh
                    command: |-
                      set -eux
                      echo ">>> Building and Testing Android App..."
                      cd Calculator
                      chmod +x gradlew
                      ./gradlew --version
                      ./gradlew clean assembleDebug
                      ls -al app/build/outputs/apk/debug/
                    resources:
                      limits:
                        memory: 4Gi
                        cpu: "2"
              - step:
                  type: RunTests
                  name: Run Unit Tests
                  identifier: JUnit_Reports
                  spec:
                    connectorRef: stupido_saurus
                    image: stupidosaurus/android-sdk-gradle:latest
                    language: Java
                    buildTool: Gradle
                    args: testDebugUnitTest
                    runOnlySelectedTests: false
                    preCommand: cd Calculator
                    resources:
                      limits:
                        memory: 4Gi
                        cpu: "2"
                    reports:
                      type: JUnit
                      spec:
                        paths:
                          - Calculator/app/build/test-results/testDebugUnitTest/*.xml
                    enableTestSplitting: false
              - step:
                  type: GCSUpload
                  name: GCSUpload_1
                  identifier: GCSUpload_1
                  spec:
                    connectorRef: GCS_Connector
                    bucket: atmosly-tfstate-atmosly-439606
                    sourcePath: Calculator/app/build/outputs/apk/debug/*.apk
                    target: harness/test/<+pipeline.sequenceId>
          caching:
            enabled: true
            paths:
              - /harness/gradle/caches
              - /harness/gradle/wrapper
          buildIntelligence:
            enabled: true
        description: ""
```

---

## YAML Fields Explained

### Top level
- `name` / `identifier` — display vs unique ID for the pipeline.  
- `projectIdentifier` / `orgIdentifier` — where the pipeline lives in Harness.

### `properties.ci.codebase`
- `connectorRef: SimpleCalc` — repo connector; used to clone code.  
- `build: <+input>` — **runtime input** (branch/PR/commit chosen at run time).  
- `sparseCheckout: []` — full checkout (no sparse paths configured).

### Stage: `Build_Android`
- `type: CI` — continuous integration stage.  
- `cloneCodebase: true` — Harness clones the repo automatically.

#### Infrastructure (KubernetesDirect)
- `connectorRef: test101` — your Kubernetes connector (via a delegate).  
- `namespace: imported` — step pods run in this namespace.  
- `automountServiceAccountToken: true` — default token mounted (fine for builds).  
- `os: Linux` — Linux containers.

#### Step: **Build APK** (`Run`)
- `connectorRef` & `image` — pulls `stupidosaurus/android-sdk-gradle:latest` (JDK, Gradle, Android SDK).  
- `shell: Sh` — the shell used to run the script.  
- `command` — enters `Calculator`, ensures `gradlew` is executable, prints versions, **builds Debug APK**, lists output.  
- `resources.limits` — caps container resources (prevents OOM / oversubscription).

#### Step: **Run Unit Tests** (`RunTests`)
- `language: Java`, `buildTool: Gradle` — enables CI insights and JUnit parsing.  
- `args: testDebugUnitTest` — standard Android unit test task (debug variant).  
- `preCommand: cd Calculator` — run Gradle in the right folder.  
- `reports: JUnit` → `paths` — where Gradle writes XML; Harness **Tests** tab parses these.  
- `resources.limits` — Memory/CPU for the test container.  
- `enableTestSplitting: false` — no parallel splitting (kept simple).

#### Step: **Upload APK** (`GCSUpload`)
- `connectorRef: GCS_Connector` — GCP credentials.  
- `bucket: atmosly-tfstate-atmosly-439606` — destination bucket.  
- `sourcePath` — the APK produced by the build step.  
- `target: harness/test/<+pipeline.sequenceId>` — unique folder per run (easy auditing).

#### Stage: `caching`
- Persists Gradle directories between runs to speed up builds.  
  > **Tip:** Set `GRADLE_USER_HOME=/harness/gradle` on the **Build** and **RunTests** steps so Gradle writes to the cached location.

#### Stage: `buildIntelligence`
- Enables Harness insights (timings, flaky tests surfaces, etc.).

---

## How to Run

### Manual
1. Open the pipeline in Harness → **Run**.  
2. Select branch/PR/commit for `<+input>`.  
3. Observe logs for each step to complete successfully.

### Trigger (on push)
- Harness → **Triggers** → New Trigger → select your repo & push event → choose this pipeline.  
- Push a commit; a new run should start automatically.

---

## What to Expect Per Step

**Build APK**
- Gradle prints version; build runs `assembleDebug`.  
- Output: `Calculator/app/build/outputs/apk/debug/app-debug.apk`.  
- Log ends with directory listing confirming the APK.

**Run Unit Tests**
- Executes `testDebugUnitTest`.  
- XML reports at: `Calculator/app/build/test-results/testDebugUnitTest/*.xml`.  
- See the **Tests** tab in the execution for parsed results.

**GCS Upload**
- Uploads the APK(s) to:  
  `gs://atmosly-tfstate-atmosly-439606/harness/test/<sequenceId>/`

---

## Cleanup

- If you created a throwaway **delegate**, remove or scale it down.  
- Delete test APKs from `gs://atmosly-tfstate-atmosly-439606/harness/test/` if you no longer need them.
