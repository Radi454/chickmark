ENV_FILE := .env
DART_DEFINES := --dart-define-from-file=$(ENV_FILE)

run:
	flutter run $(DART_DEFINES)

run-ios:
	flutter run $(DART_DEFINES) -d iPhone

run-android:
	flutter run $(DART_DEFINES) -d android

build-ios:
	flutter build ios $(DART_DEFINES)

build-apk:
	flutter build apk $(DART_DEFINES)

.PHONY: run run-ios run-android build-ios build-apk
