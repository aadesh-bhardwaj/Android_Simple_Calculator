FROM gradle:7.5.0-jdk17

# Install Android SDK
RUN apt-get update && apt-get install -y wget unzip
RUN mkdir -p /usr/local/android-sdk/cmdline-tools \
    && wget -O /tmp/cmd.zip https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip \
    && unzip -q /tmp/cmd.zip -d /usr/local/android-sdk/cmdline-tools \
    && yes | /usr/local/android-sdk/cmdline-tools/cmdline-tools/bin/sdkmanager --licenses \
    && /usr/local/android-sdk/cmdline-tools/cmdline-tools/bin/sdkmanager \
        "platform-tools" "platforms;android-30" "build-tools;30.0.3"

ENV ANDROID_HOME=/usr/local/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/platform-tools

WORKDIR /app