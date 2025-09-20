
# 📱 Android CI with Harness — End-to-End Documentation  
### *(Build, Test, Publish to GCS)*

This document explains your Android Continuous Integration setup in **Harness**, including how to **reproduce it from scratch**, and what each field in your final **YAML pipeline** does.

> **Note**: CD/distribution is intentionally skipped. This CI pipeline:
> - Builds a **Debug APK**
> - Runs **JUnit unit tests**
> - Uploads the APK to **Google Cloud Storage (GCS)**

---

## 🚀 What This Pipeline Does (At a Glance)

1. Clones your Android repo via **Harness Codebase connector**.
2. Builds a **Debug APK** with Gradle inside a container preloaded with Android SDK + JDK.
3. Runs **JUnit tests** and publishes results to the Harness UI.
4. Uploads the APK to:
   ```
   gs://atmosly-tfstate-atmosly-439606/harness/test/<pipeline-sequence-id>/
   ```
5. (Optional) Triggered automatically on Git push.

---

## ✅ Prerequisites

- A **Harness account**, project, and organization.
- The following **connectors** configured:
  
  | Purpose             | Connector Name       | Notes |
  |---------------------|----------------------|-------|
  | Git Repo            | `SimpleCalc`         | GitHub/GitLab/Bitbucket |
  | Kubernetes Cluster  | `test101`            | Cluster with a delegate |
  | Docker Registry     | `stupido_saurus`     | Needed if image is private |
  | GCS Storage         | `GCS_Connector`      | Write access to GCS bucket |

- Repo structure:
  ```
  Calculator/
    └── app/
    └── gradlew
  ```
- Gradle config for reliable test runs in `app/build.gradle`:
  ```groovy
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

---

## 🔧 Reproducible Setup Steps

### 1. Create the Connectors

- **Codebase**: OAuth or token-based access to your repo.
- **Kubernetes**: Install a Harness delegate (stage uses namespace `imported`).
- **Docker**: Only needed for private images.
- **GCS**: Use a Service Account JSON with `Storage Object Admin` permission.

---

### 2. Add the Pipeline

- In Harness, go to your **CI project** → Pipelines → **Create new**.
- Paste the YAML (below) into the pipeline editor.
- Save.

---

### 3. (Optional) Create a Trigger

- UI → Triggers → Git Provider
- Event: **Push**
- Add **branch filter** → Select this pipeline.

---

## ▶️ How to Run & Validate

### Manual Run
- Click **Run**, provide input (branch, PR, or commit).
- Watch logs:
  - ✅ APK build successful
  - ✅ JUnit test results appear
  - ✅ APK uploaded to GCS

### Validate Outputs

- **Harness UI → Tests tab**: JUnit results.
- **GCS**: Folder `harness/test/<sequenceId>/` contains `app-debug.apk`.

---

## 🧼 (Optional) Post-Run Cleanup

- Remove test artifacts from GCS.
- Scale down/remove delegate if it was created just for this CI pipeline.

---

## 📄 Final YAML (CI Pipeline)

<details>
<summary><strong>Click to expand</strong></summary>

```yaml
pipeline:
  identifier: SimpleCalc
  name: SimpleCalc
  projectIdentifier: default_project
  orgIdentifier: default
  properties:
    ci:
      codebase:
        connectorRef: SimpleCalc
        build:
          type: branch
          spec:
            branch: <+trigger.branch>
        sparseCheckout: []
  stages:
    - stage:
        identifier: Build_Android
        type: CI
        name: Build_Android
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
                  identifier: Build_APK
                  type: Run
                  name: Build APK
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
                  identifier: JUnit_Reports
                  type: RunTests
                  name: Run Unit Tests
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
                  identifier: GCSUpload_1
                  type: GCSUpload
                  name: GCSUpload_1
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
</details>

---

## 🔍 YAML Explanation (Line-by-Line)

pipeline (top level)

name / identifier: Human-readable vs unique ID for the pipeline.

projectIdentifier / orgIdentifier: Which Project/Org in Harness holds this pipeline.

properties.ci.codebase

connectorRef: SimpleCalc: Code repository connector. Harness clones the repo through this connector.

build: <+input>: A runtime input; when you press Run, you choose branch/PR/commit.

sparseCheckout: []: Not using sparse checkout (full clone).

stages[0] — Build_Android (CI stage)

type: CI: This is a CI stage (not CD).

spec.cloneCodebase: true: Harness will automatically clone the repository at stage start.

infrastructure

type: KubernetesDirect: The stage runs each step as a Kubernetes pod on a cluster.

spec.connectorRef: test101: Kubernetes connector pointing to your cluster with a delegate installed.

namespace: imported: Pods run in this namespace.

automountServiceAccountToken: true: Mounts default service account token in step pods (often fine for build pods).

nodeSelector: {}: No specific node selection.

os: Linux: Container OS for steps.

execution.steps[0] — Build APK (Run)

type: Run: A general container step.

connectorRef: stupido_saurus: Docker registry connector for pulling the image (omit if image public).

image: stupidosaurus/android-sdk-gradle:latest: Your custom image with JDK/Gradle/Android SDK preinstalled.

shell: Sh: Shell for the command.

command:

cd Calculator: Enter the project subfolder.

chmod +x gradlew: Ensure wrapper is executable.

./gradlew --version: Debug info in logs.

./gradlew clean assembleDebug: Build a Debug APK.

ls -al app/build/outputs/apk/debug/: Confirm artifact exists.

resources.limits: Caps pod container resources (prevents OOM / oversubscription).

execution.steps[1] — Run Unit Tests (RunTests)

type: RunTests: Structured test step that surfaces results in the Tests tab.

connectorRef / image: Same container image as build step (consistent toolchain).

language: Java / buildTool: Gradle: Enables CI insights for Java/Gradle tests.

args: testDebugUnitTest: Runs unit tests for the debug variant (Android convention).

runOnlySelectedTests: false: Ensures all tests run (no test selection/impact analysis).

preCommand: cd Calculator: Enter project directory before running Gradle.

reports.type: JUnit with paths: Where Gradle emits JUnit XML (app/build/test-results/testDebugUnitTest/*.xml). Harness parses this into the Tests UI.

resources.limits: Memory/CPU for the test container.

enableTestSplitting: false: Disables splitting across multiple containers.

execution.steps[2] — Upload APK (GCSUpload)

type: GCSUpload: Built-in step to push files to GCS.

connectorRef: GCS_Connector: GCP connector with write permission to the bucket.

bucket: atmosly-tfstate-atmosly-439606: Target bucket.

sourcePath: Calculator/app/build/outputs/apk/debug/*.apk: Local path (inside the build container’s workspace).

target: harness/test/<+pipeline.sequenceId>: Destination prefix; each run gets a unique folder using the pipeline’s sequence ID.

Stage-level caching

enabled: true: Turns on Harness cache for this stage.

paths: Directories to persist between runs. You chose:

/harness/gradle/caches

/harness/gradle/wrapper

Tip: To fully leverage these, set GRADLE_USER_HOME=/harness/gradle in the Build and RunTests steps (spec.envVariables) so Gradle writes to the cached location.

Stage-level buildIntelligence

enabled: true: Harness will collect insights (e.g., timing, flaky tests visibility).

---

## 🛠️ Troubleshooting & Tips

| Problem | Solution |
|--------|----------|
| **ImagePullBackOff** | Ensure Docker connector + permissions are valid |
| **Gradle Cache not working** | Set `GRADLE_USER_HOME=/harness/gradle` in step `envVariables` |
| **Tests not visible** | Ensure XML path is correct & `testDebugUnitTest` is run |
| **Upload fails** | Check GCS_Connector permissions & `sourcePath` |
| **OOM errors** | Increase `resources.limits.memory` to 6–8Gi |

---

## 🧾 What’s Out of Scope

> CD, Approval steps, Firebase/TestFlight upload.

This CI pipeline skips distribution. If needed later, we can provide a Firebase CLI deployment step with secret integration.

---

## 🧩 Appendix: Optional Enhancements

- **Static Analysis**: Add `./gradlew lint` as a step.
- **Test Coverage**: Integrate Jacoco & upload XML to Harness.
- **Matrix Builds**: Parallel flavors via strategy matrix.
- **Advanced Versioning**:
  ```yaml
  target: "tictactoe/<+pipeline.sequenceId>/<+codebase.branch>/<+pipeline.startTs>/"
  ```

---

## ✅ Summary

You now have a fully working Harness CI pipeline that:

✅ Builds a consistent **Android Debug APK**  
✅ Runs **JUnit tests** and surfaces results in UI  
✅ Uploads the artifact to **GCS** with versioned paths  
✅ Can be **auto-triggered** on Git push  
