cmake_minimum_required(VERSION 3.21)
project(mcfly-display VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 6.6 for Sparkline's curve renderer (Shape.preferredRendererType); the Pi runs
# Debian Trixie's 6.8. With an older Qt the QML would build and then not load.
find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Network Qml Quick Concurrent WebSockets ShaderTools)
qt_standard_project_setup()
# Qt 6.8+ (Raspberry Pi OS / Debian Trixie) warns unless this is set: give each
# QML subfolder its own qmldir. Qt 6.6 and 6.7 don't know it.
if(QT_KNOWN_POLICY_QTP0004)
    qt_policy(SET QTP0004 NEW)
endif()

option(MCFLY_BUILD_TESTS "Build the display's unit tests" ON)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set(MCFLY_WARNINGS -Wall -Wextra)
endif()

# Networking, streaming and voice plumbing: shared by the app and the tests.
add_library(mcfly-core STATIC
    src/backend/SupabaseClient.h   src/backend/SupabaseClient.cpp
    src/backend/SseParser.h        src/backend/SseParser.cpp
    src/models/ChatModel.h         src/models/ChatModel.cpp
    src/voice/VoiceClient.h        src/voice/VoiceClient.cpp
)
target_include_directories(mcfly-core PUBLIC src)
target_compile_options(mcfly-core PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(mcfly-core PUBLIC Qt6::Core Qt6::Network Qt6::WebSockets)

# QR codes (Project Nayuki's generator, MIT; display/third_party/qrcodegen).
add_library(mcfly-qr STATIC
    third_party/qrcodegen/qrcodegen.hpp third_party/qrcodegen/qrcodegen.cpp
    src/models/QrImageProvider.h    src/models/QrImageProvider.cpp
)
target_include_directories(mcfly-qr PUBLIC src third_party/qrcodegen)
target_link_libraries(mcfly-qr PUBLIC Qt6::Gui Qt6::Quick)

qt_add_executable(mcfly-display
    src/main.cpp
    src/models/FeedStore.h         src/models/FeedStore.cpp
    src/models/Assistant.h         src/models/Assistant.cpp
    src/models/SettingsBridge.h    src/models/SettingsBridge.cpp
    src/models/HomeGlance.h        src/models/HomeGlance.cpp
    src/hardware/DisplayController.h src/hardware/DisplayController.cpp
    src/hardware/SystemController.h src/hardware/SystemController.cpp
    src/hardware/PanelPower.h      src/hardware/PanelPower.cpp
)

target_include_directories(mcfly-display PRIVATE src)

# Turning an HDMI panel off when the screen sleeps (DPMS) goes through Qt's
# platform screen, a private API: qt6-base-private-dev. Without it the
# sleeping screen is only black. Qt 6.9 and later ship it as its own package.
if(NOT TARGET Qt6::GuiPrivate)
    set(QT_NO_PRIVATE_MODULE_WARNING ON)
    find_package(Qt6GuiPrivate QUIET)
endif()
set(MCFLY_PANEL_POWER OFF)
if(TARGET Qt6::GuiPrivate)
    # Plain paths up to Qt 6.7. From 6.8 each one sits in a generator
    # expression, $<$<BOOL:...>:path>, so take the paths out of the text.
    get_target_property(mcfly_qpa_dirs Qt6::GuiPrivate INTERFACE_INCLUDE_DIRECTORIES)
    string(REGEX MATCHALL "[^;:<>$]+/QtGui/[^;:<>$]+" mcfly_qpa_dirs "${mcfly_qpa_dirs}")
    foreach(dir IN LISTS mcfly_qpa_dirs)
        if(EXISTS "${dir}/qpa/qplatformscreen.h")
            set(MCFLY_PANEL_POWER ON)
        endif()
    endforeach()
endif()
if(MCFLY_PANEL_POWER)
    message(STATUS "HDMI panel power: on (Qt private headers found)")
    target_compile_definitions(mcfly-display PRIVATE MCFLY_PANEL_POWER)
    target_link_libraries(mcfly-display PRIVATE Qt6::GuiPrivate)
else()
    message(STATUS "HDMI panel power: off. Qt private headers not found (qt6-base-private-dev): an HDMI panel stays lit while the screen sleeps")
endif()
target_compile_options(mcfly-display PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(mcfly-display PRIVATE MCFLY_VERSION="${PROJECT_VERSION}")

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Glass.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(mcfly-display
    URI McFly
    VERSION 1.0
    RESOURCE_PREFIX /
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/Glass.qml
        qml/components/Card.qml
        qml/components/NavRail.qml
        qml/components/PillButton.qml
        qml/components/Icon.qml
        qml/components/IconButton.qml
        qml/components/Lens.qml
        qml/components/Glow.qml
        qml/components/GradientTile.qml
        qml/components/AuroraGlow.qml
        qml/components/Backdrop.qml
        qml/components/SpectrumGlow.qml
        qml/components/Sparkline.qml
        qml/components/IntradayChart.qml
        qml/components/StoryCard.qml
        qml/components/Tag.qml
        qml/components/SegmentedControl.qml
        qml/components/Page.qml
        qml/components/AnimatedNumber.qml
        qml/components/Toggle.qml
        qml/components/FormDialog.qml
        qml/components/FormField.qml
        qml/components/FocusFlickable.qml
        qml/components/Layer.qml
        qml/components/ScreenHeader.qml
        qml/components/MasterDetail.qml
        qml/components/ChipRow.qml
        qml/components/EmptyState.qml
        qml/components/QrPanel.qml
        qml/components/SuggestionChips.qml
        qml/screens/HomeScreen.qml
        qml/components/Reveal.qml
        qml/components/Ring.qml
        qml/components/StatusDot.qml
        qml/components/InsightLine.qml
        qml/components/HealthStrip.qml
        qml/screens/HomeLayouts.qml
        qml/screens/HomeBento.qml
        qml/screens/HomeAssistant.qml
        qml/screens/BriefsScreen.qml
        qml/screens/MarketsScreen.qml
        qml/screens/NewsScreen.qml
        qml/screens/SetupScreen.qml
        qml/screens/ProjectsScreen.qml
        qml/screens/DashboardsScreen.qml
        qml/screens/CalendarScreen.qml
        qml/screens/AssistantPanel.qml
        qml/screens/QuickAnswer.qml
        qml/screens/ReminderCard.qml
        qml/screens/SettingsSheet.qml
        qml/screensaver/ScreenSaver.qml
        qml/screensaver/ClockSaver.qml
        qml/screensaver/HeadlinesSaver.qml
        qml/screensaver/AmbientSaver.qml
    RESOURCES
        resources/demo/feed.json
        # The on-screen keyboard is optional at run time, so these are not
        # compiled: KeyboardPanel loads them only when the module is there.
        qml/components/KeyboardPanel.qml
        qml/keyboard/layouts/en_US/main.qml
        qml/keyboard/layouts/en_US/symbols.qml
        qml/keyboard/layouts/en_US/digits.qml
        qml/keyboard/layouts/en_US/numbers.qml
        qml/keyboard/layouts/en_US/dialpad.qml
)

# The keyboard's look, where VirtualKeyboardSettings.styleName finds it:
# QtQuick/VirtualKeyboard/Styles/<name>/style.qml under an import path
# (qrc:/keyboard, added in main.cpp).
set_source_files_properties(qml/keyboard/style.qml
    PROPERTIES QT_RESOURCE_ALIAS QtQuick/VirtualKeyboard/Styles/mcfly/style.qml)
qt_add_resources(mcfly-display "keyboard_style"
    PREFIX /keyboard
    FILES qml/keyboard/style.qml
)

# ShaderEffect fragment shaders, baked to .qsb at build time (qrc:/McFly/shaders/).
qt_add_shaders(mcfly-display "shaders"
    PREFIX /McFly
    FILES
        shaders/gradienttile.frag
        shaders/spectrumglow.frag
        shaders/aurora.frag
        shaders/glow.frag
        shaders/lens.frag
        shaders/arc.frag
        shaders/ribbons.frag
        shaders/dawn.frag
        shaders/silk.frag
        shaders/pillars.frag
)

target_link_libraries(mcfly-display PRIVATE mcfly-core mcfly-qr
    Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::Concurrent Qt6::WebSockets)

install(TARGETS mcfly-display RUNTIME DESTINATION bin)
install(PROGRAMS deploy/mcfly-system DESTINATION libexec)

if(MCFLY_BUILD_TESTS)
    find_package(Qt6 6.6 QUIET COMPONENTS Test)
    if(Qt6Test_FOUND)
        enable_testing()
        add_subdirectory(tests)
    else()
        message(STATUS "Qt Test not found; skipping the display unit tests")
    endif()
endif()
