.PHONY: app clean

app:
	mkdir -p build/Orbit.iconset
	swift Tools/MakeOrbitIcon.swift build/Orbit.iconset
	iconutil -c icns build/Orbit.iconset -o Resources/Orbit.icns
	rm -rf build/Orbit.iconset
	xcodebuild -quiet -project Orbit.xcodeproj -scheme Orbit -configuration Release -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- build
	rm -rf build/Orbit.app
	ditto build/DerivedData/Build/Products/Release/Orbit.app build/Orbit.app
	ditto -c -k --sequesterRsrc --keepParent build/Orbit.app build/Orbit.zip
	@echo "Built build/Orbit.app"

clean:
	rm -rf .build build
