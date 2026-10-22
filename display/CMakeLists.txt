cmake_minimum_required(VERSION 3.21)
project(mcfly-display VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 6.7 for ScaledShader (QQuickRhiItem); the Pi runs Debian Trixie's 6.8. With
# an older Qt the QML would build and then not load.
find_package(Qt6 6.7 REQUIRED COMPONENTS Core Gui Network Qml Quick Concurrent WebSockets ShaderTools)
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

# Penguin March (qml/games/PenguinMarch.qml): the rules and the levels, and
# the view that draws them. A library so tests/tst_penguins.cpp can replay
# every level's solution without a window.
add_library(mcfly-penguins STATIC
    src/games/PenguinSim.h         src/games/PenguinSim.cpp
    src/games/PenguinLevels.h      src/games/PenguinLevels.cpp
    src/games/PenguinArt.h         src/games/PenguinArt.cpp
    src/games/PenguinWorld.h       src/games/PenguinWorld.cpp
)
target_include_directories(mcfly-penguins PUBLIC src)
target_compile_options(mcfly-penguins PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(mcfly-penguins PUBLIC Qt6::Gui Qt6::Quick)

# Color by Number's pictures, progress and board (qml/games/ColorByNumber.qml).
# The pictures are src/games/colorbynumber.txt, built in as a string: an edit
# to the file reconfigures and rebuilds.
file(READ src/games/colorbynumber.txt MCFLY_COLOR_PICTURES)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS src/games/colorbynumber.txt)
configure_file(src/games/ColorByNumberPictures.cpp.in ${CMAKE_CURRENT_BINARY_DIR}/ColorByNumberPictures.cpp @ONLY)
add_library(mcfly-colors STATIC
    src/games/ColorByNumber.h      src/games/ColorByNumber.cpp
    ${CMAKE_CURRENT_BINARY_DIR}/ColorByNumberPictures.cpp
)
target_include_directories(mcfly-colors PUBLIC src)
target_compile_options(mcfly-colors PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(mcfly-colors PUBLIC Qt6::Gui Qt6::Quick)

# ScaledShader: a ShaderEffect shader drawn small and scaled up without a
# layer's extra frame (the screen savers' skies). A QQuickRhiItem drawing
# through QRhi, whose headers come with Qt's private ones
# (qt6-base-private-dev, as for the panel's power below). A library so the
# QML tests can register it too.
if(NOT TARGET Qt6::GuiPrivate)
    set(QT_NO_PRIVATE_MODULE_WARNING ON)
    find_package(Qt6GuiPrivate QUIET)
endif()
if(NOT TARGET Qt6::GuiPrivate)
    message(FATAL_ERROR "Qt's private headers not found (qt6-base-private-dev): ScaledShader draws through QRhi")
endif()
add_library(mcfly-graphics STATIC
    src/graphics/ScaledShader.h    src/graphics/ScaledShader.cpp
)
target_include_directories(mcfly-graphics PUBLIC src)
target_compile_options(mcfly-graphics PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(mcfly-graphics PUBLIC Qt6::Gui Qt6::GuiPrivate Qt6::Qml Qt6::Quick)

qt_add_executable(mcfly-display
    src/main.cpp
    src/models/FeedStore.h         src/models/FeedStore.cpp
    src/models/Assistant.h         src/models/Assistant.cpp
    src/models/SettingsBridge.h    src/models/SettingsBridge.cpp
    src/models/HomeGlance.h        src/models/HomeGlance.cpp
    src/models/ArticleReader.h     src/models/ArticleReader.cpp
    src/hardware/DisplayController.h src/hardware/DisplayController.cpp
    src/hardware/SystemController.h src/hardware/SystemController.cpp
    src/hardware/PanelPower.h      src/hardware/PanelPower.cpp
    src/hardware/PerfMonitor.h     src/hardware/PerfMonitor.cpp
    src/hardware/StopSignals.h     src/hardware/StopSignals.cpp
    src/games/FourInARowEngine.h   src/games/FourInARowEngine.cpp
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

# Open-source games kept as their authors wrote them (display/games/README.md).
# GamesScreen.qml loads them from the resources when one is opened.
file(GLOB_RECURSE mcfly_vendored_games RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS
    games/samegame/*.qml games/samegame/*.js games/samegame/qmldir games/samegame/*.png
    games/maroon/*.qml games/maroon/*.js games/maroon/*.png games/maroon/*.wav)

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
        qml/components/FluxMark.qml
        qml/components/Wordmark.qml
        qml/components/PillButton.qml
        qml/components/Icon.qml
        qml/components/IconButton.qml
        qml/components/Lens.qml
        qml/components/Glow.qml
        qml/components/GradientTile.qml
        qml/components/AuroraGlow.qml
        qml/components/Backdrop.qml
        qml/components/Weather.qml
        qml/components/SpectrumGlow.qml
        qml/components/Sparkline.qml
        qml/components/IntradayChart.qml
        qml/components/StoryCard.qml
        qml/components/Tag.qml
        qml/components/SegmentedControl.qml
        qml/components/TabStrip.qml
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
        qml/components/MotionClock.qml
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
        qml/screens/GamesScreen.qml
        qml/games/Game2048.qml
        qml/games/TrafficJam.qml
        qml/games/TicTacToe.qml
        qml/games/FourInARow.qml
        qml/games/ColorByNumber.qml
        qml/games/PenguinMarch.qml
        games/2048/game.js
        games/traffic/rush.js
        games/traffic/puzzles.js
        qml/games/ScoopShop.qml
        qml/games/ScoopTreat.qml
        qml/games/ScoopCrew.qml
        qml/games/ScoopAwning.qml
        qml/games/ScoopStock.qml
        qml/games/scoops.js
    RESOURCES
        resources/demo/feed.json
        resources/fonts/Exo2-BlackItalic.ttf
        ${mcfly_vendored_games}
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

# ShaderEffect fragment shaders, baked to .qsb at build time (qrc:/McFly/shaders/),
# and ScaledShader's vertex stage.
qt_add_shaders(mcfly-display "shaders"
    PREFIX /McFly
    FILES
        shaders/scaled.vert
        shaders/gradienttile.frag
        shaders/spectrumglow.frag
        shaders/spectrumglow.vert
        shaders/aurora.frag
        shaders/glow.frag
        shaders/lens.frag
        shaders/arc.frag
        shaders/arc.vert
        shaders/ribbons.frag
        shaders/dawn.frag
        shaders/silk.frag
        shaders/pillars.frag
)

target_link_libraries(mcfly-display PRIVATE mcfly-core mcfly-qr mcfly-penguins mcfly-colors mcfly-graphics
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
