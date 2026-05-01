ENV_FILE := .env
DART_DEFINES := --dart-define-from-file=$(ENV_FILE)
WEB_HOST ?= 127.0.0.1
WEB_PORT ?= 57861

run:
	flutter run $(DART_DEFINES)

run-web:
	WEB_HOST=$(WEB_HOST) WEB_PORT=$(WEB_PORT) scripts/run_flutter_web.sh

run-ios:
	flutter run $(DART_DEFINES) -d iPhone

run-android:
	flutter run $(DART_DEFINES) -d android

build-ios:
	flutter build ios $(DART_DEFINES)

build-apk:
	flutter build apk $(DART_DEFINES)

.PHONY: run run-web run-ios run-android build-ios build-apk
