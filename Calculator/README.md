Android CI with Harness — End-to-End Documentation (Build, Test, Publish to GCS)

This document explains your Android Continuous Integration setup in Harness, how to reproduce it from scratch, and what each field in your final YAML does. You explicitly skip CD/distribution; the pipeline builds a debug APK, runs JUnit unit tests, and uploads the APK to Google Cloud Storage (GCS).

What this pipeline does (at a glance)

Clones your Android repo (via Harness Codebase connector).

Builds a Debug APK with Gradle inside a container that already has the Android SDK + JDK.

Runs JUnit unit tests and publishes JUnit XML results to the Harness Tests tab.

Uploads the APK to a versioned folder in GCS: harness/test/<pipeline-sequence-id>.

(Optional in UI): A trigger auto-runs the pipeline on Git push.

Prerequisites

A Harness account, Project and Org.

Connectors set up:

Code Repo: SimpleCalc → your GitHub/GitLab/Bitbucket repo.

Kubernetes: test101 → points to a cluster with a Harness delegate installed.

Docker Registry (if the image is private): stupido_saurus → access to stupidosaurus/android-sdk-gradle:latest.

GCS: GCS_Connector → a Service Account with write access to your bucket atmosly-tfstate-atmosly-439606.

Source layout: your repo root contains a folder Calculator/ with a Gradle Android app module app/ and a Gradle wrapper (gradlew).

Gradle config for unit tests (module app/build.gradle):

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


(This ensures JUnit tests run reliably in CI.)

Reproducible Setup Steps

Create the connectors

Code (SimpleCalc): OAuth/personal token pointing to your repo.

Kubernetes (test101): Install a delegate in your cluster (any namespace). The stage below uses namespace imported.

Docker (stupido_saurus): Only needed if your image is private. Otherwise omit connectorRef in steps.

GCS (GCS_Connector): Use a Service Account JSON with Storage Object Admin (or finer-grained write perms) on the target bucket.

Add the pipeline

Create a CI pipeline in your Harness project.

Paste the final YAML (below) and save.

(Optional) Create a Trigger

UI → Triggers → Git provider → event Push → branch filter → select this pipeline.

You already verified this works (great!).

Run the pipeline

Click Run, provide the build input (branch/PR/commit as prompted).

Watch logs; ensure: APK built, JUnit test results appear, and APK uploaded to GCS.

Verify outputs

Harness Tests tab shows JUnit results.

GCS bucket folder harness/test/<sequenceId>/ has app-debug.apk.

(After submission) Cleanup (optional): delete test artifacts from GCS, scale down/remove delegate if it was created only for this assignment.

Final YAML (for reference)
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

Line-by-Line YAML Explanation
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

How to Run & Validate

Manual run

Open the pipeline → Run → pick branch/commit (runtime input).

Confirm the three steps succeed.

Validate tests

After run completes, open the Tests tab → check test counts, pass/fail, durations.

Validate artifact

Check your GCS bucket → harness/test/<sequenceId>/app-debug.apk.

Validate trigger (optional)

Push a commit to the branch your Trigger watches → confirm a new run starts → verify outputs as above.

Troubleshooting & Tips

ImagePullBackOff: Ensure stupidosaurus/android-sdk-gradle:latest is reachable. If private, stupido_saurus must be a valid Docker connector with credentials.

Gradle cache not speeding up builds: Add

envVariables:
  GRADLE_USER_HOME: /harness/gradle


to both Build APK and Run Unit Tests steps so the declared cache paths are actually used.

No tests showing: Make sure args: testDebugUnitTest is used, and XML reports exist at app/build/test-results/testDebugUnitTest/.

GCS upload fails: Verify GCS_Connector permissions and that sourcePath matches the actual output path in logs.

OOM / slow builds: Increase resources.limits.memory to 6–8Gi or enable Gradle daemon flags if needed.

What’s intentionally out of scope (per your choice)

CD/Distribution (Firebase/TestFlight) + Approval steps.
The assignment doc includes these for full marks, but you chose to keep CI-only. If you later need maximum compliance, add a CD stage with an Approval + Firebase CLI upload using secrets stored in Harness (we can provide a ready-to-paste stage when you want it).

Appendix — Optional Enhancements

Static analysis: Add a Run step with ./gradlew lint before building.

Coverage: Apply the Jacoco plugin and publish XML to Harness for code coverage visibility.

Matrix builds: Build multiple flavors in parallel (e.g., assembleDebug for different productFlavors).

Artifact versioning: Add branch, commit, and timestamp in target for auditability:

target: "tictactoe/<+pipeline.sequenceId>/<+codebase.branch>/<+pipeline.startTs>/"

Summary

You now have a clean, reproducible CI pipeline that:

Builds your Android Debug APK in a consistent container,

Runs JUnit unit tests and publishes results to Harness,

Uploads artifacts to GCS in a versioned path,

Can be auto-triggered on Git push.
