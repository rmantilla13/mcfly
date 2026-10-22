# Unit tests: `ctest --test-dir build/display` (or run the binaries directly).
qt_add_executable(tst_system tst_system.cpp
    ../src/hardware/SystemController.h
    ../src/hardware/SystemController.cpp)
target_include_directories(tst_system PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_system PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_system PRIVATE Qt6::Network Qt6::Test)
add_test(NAME tst_system COMMAND tst_system)
set_tests_properties(tst_system PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

qt_add_executable(tst_display tst_display.cpp
    ../src/hardware/DisplayController.h
    ../src/hardware/DisplayController.cpp)
target_include_directories(tst_display PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_display PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_display PRIVATE Qt6::Test)
add_test(NAME tst_display COMMAND tst_display)
set_tests_properties(tst_display PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

add_test(NAME system_helper COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/system_helper_test.sh)
add_test(NAME kiosk_boot COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/kiosk_boot_test.sh)
# The player's stop helper walks process trees with GNU ps; the Pi and CI are Linux.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    add_test(NAME bootscreen COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/bootscreen_test.sh)
endif()

foreach(name tst_sseparser tst_streamfunction tst_voiceclient)
    qt_add_executable(${name} ${name}.cpp)
    target_compile_options(${name} PRIVATE ${MCFLY_WARNINGS})
    target_link_libraries(${name} PRIVATE mcfly-core Qt6::Test)
    add_test(NAME ${name} COMMAND ${name})
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")
endforeach()

# Penguin March's rules on small made-up levels, and every level won by its
# recorded solution.
qt_add_executable(tst_penguins tst_penguins.cpp)
target_compile_options(tst_penguins PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_penguins PRIVATE mcfly-penguins Qt6::Test)
add_test(NAME tst_penguins COMMAND tst_penguins)
set_tests_properties(tst_penguins PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# Color by Number: every picture well formed, painting, progress saved and
# restored, and the board's zoom, pan and touch.
qt_add_executable(tst_colors tst_colors.cpp)
target_compile_options(tst_colors PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_colors PRIVATE mcfly-colors Qt6::Test)
add_test(NAME tst_colors COMMAND tst_colors)
set_tests_properties(tst_colors PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# QR codes: the modules of a known text, and the image provider's scaling.
qt_add_executable(tst_qrcode tst_qrcode.cpp)
target_compile_options(tst_qrcode PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_qrcode PRIVATE mcfly-qr Qt6::Test)
add_test(NAME tst_qrcode COMMAND tst_qrcode)
set_tests_properties(tst_qrcode PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The feed store in live mode, against a fake Supabase (FakeServer.h), and
# in demo mode; the assistant against a fake `assistant` function.
foreach(name tst_feedstore tst_assistant)
    qt_add_executable(${name} ${name}.cpp FakeServer.h
        ../src/models/FeedStore.h  ../src/models/FeedStore.cpp
        ../src/models/Assistant.h  ../src/models/Assistant.cpp
    )
    target_compile_options(${name} PRIVATE ${MCFLY_WARNINGS})
    target_link_libraries(${name} PRIVATE mcfly-core Qt6::Gui Qt6::Test)
    # The demo data, at the path the app has it.
    qt_add_resources(${name} "demo_data_${name}"
        PREFIX /McFly
        BASE ${PROJECT_SOURCE_DIR}
        FILES ${PROJECT_SOURCE_DIR}/resources/demo/feed.json)
    add_test(NAME ${name} COMMAND ${name})
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")
endforeach()

# QML tests copy the files they use into a McFly module directory of their
# own (<dir>/McFly), since the app's module is built into the binary.
function(mcfly_test_qml_module dir)
    set(qmldir "module McFly\n")
    foreach(file ${ARGN})
        configure_file(${PROJECT_SOURCE_DIR}/qml/${file} ${dir}/McFly/${file} COPYONLY)
        get_filename_component(type ${file} NAME_WE)
        if(type STREQUAL "Theme" OR type STREQUAL "Glass")
            string(APPEND qmldir "singleton ")
        endif()
        string(APPEND qmldir "${type} 1.0 ${file}\n")
    endforeach()
    file(WRITE ${dir}/McFly/qmldir "${qmldir}")
endfunction()

# The wake-word card (QuickAnswer.qml) with the real assistant and voice client.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml
    Theme.qml Glass.qml components/Lens.qml components/Icon.qml components/IconButton.qml components/PillButton.qml
    components/SpectrumGlow.qml screens/QuickAnswer.qml)

qt_add_executable(tst_quickanswer tst_quickanswer.cpp
    ../src/models/FeedStore.h  ../src/models/FeedStore.cpp
    ../src/models/Assistant.h  ../src/models/Assistant.cpp
)
target_compile_options(tst_quickanswer PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_quickanswer PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml")
target_link_libraries(tst_quickanswer PRIVATE mcfly-core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_resources(tst_quickanswer "demo_data_quick"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/resources/demo/feed.json)
qt_add_shaders(tst_quickanswer "quick_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.vert ${PROJECT_SOURCE_DIR}/shaders/lens.frag)
add_test(NAME tst_quickanswer COMMAND tst_quickanswer)
set_tests_properties(tst_quickanswer PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The wall dialogs' shell (FormDialog.qml) under a Layer, the way Main.qml
# stacks the on-screen keyboard over dialogs; and closing when the display
# goes idle.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-dialogs
    Theme.qml Glass.qml components/Lens.qml components/PillButton.qml components/FormField.qml
    components/FocusFlickable.qml components/FormDialog.qml components/Layer.qml)
qt_add_executable(tst_dialogs tst_dialogs.cpp)
target_compile_options(tst_dialogs PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_dialogs PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-dialogs")
target_link_libraries(tst_dialogs PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_dialogs "dialogs_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/lens.frag)
add_test(NAME tst_dialogs COMMAND tst_dialogs)
set_tests_properties(tst_dialogs PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# Motion: the palette's fade lengths, GradientTile's drift and SpectrumGlow's
# idle cap, against a stand-in DisplayController.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-motion
    Theme.qml components/GradientTile.qml components/SpectrumGlow.qml components/MotionClock.qml)
qt_add_executable(tst_motion tst_motion.cpp)
target_compile_options(tst_motion PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_motion PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-motion")
target_link_libraries(tst_motion PRIVATE mcfly-graphics Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_motion "motion_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/gradienttile.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.vert)
add_test(NAME tst_motion COMMAND tst_motion)
set_tests_properties(tst_motion PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The screens' motion and layouts (Home, Boards, Briefs) against the real
# store at a fixed time of day: the reveal, the insight line, Home's
# countdown and now marker, board tiles from boardLayout, the Briefs outline,
# the nav's thinking ring, Setup's ambient loops.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-screens
    Theme.qml Glass.qml components/Lens.qml components/Icon.qml components/IconButton.qml components/PillButton.qml
    components/SpectrumGlow.qml components/GradientTile.qml components/Sparkline.qml
    components/Ring.qml components/StatusDot.qml components/MotionClock.qml components/Reveal.qml components/InsightLine.qml
    components/HealthStrip.qml components/SuggestionChips.qml components/FocusFlickable.qml
    components/QrPanel.qml components/EmptyState.qml components/ScreenHeader.qml components/ChipRow.qml
    components/MasterDetail.qml components/Tag.qml components/NavRail.qml components/FluxMark.qml components/Wordmark.qml components/FormField.qml
    screens/HomeScreen.qml screens/DashboardsScreen.qml screens/BriefsScreen.qml screens/HomeAssistant.qml
    screens/SetupScreen.qml
    screensaver/ScreenSaver.qml screensaver/AmbientSaver.qml screensaver/ClockSaver.qml screensaver/HeadlinesSaver.qml
    components/Backdrop.qml components/AuroraGlow.qml components/Weather.qml)
qt_add_executable(tst_screens tst_screens.cpp
    ../src/models/FeedStore.h  ../src/models/FeedStore.cpp
    ../src/models/Assistant.h  ../src/models/Assistant.cpp
    ../src/models/HomeGlance.h ../src/models/HomeGlance.cpp
)
target_compile_options(tst_screens PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_screens PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-screens")
target_link_libraries(tst_screens PRIVATE mcfly-core mcfly-graphics Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_resources(tst_screens "demo_data_screens"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/resources/demo/feed.json)
qt_add_shaders(tst_screens "screens_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/gradienttile.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.vert
          ${PROJECT_SOURCE_DIR}/shaders/lens.frag ${PROJECT_SOURCE_DIR}/shaders/arc.frag ${PROJECT_SOURCE_DIR}/shaders/arc.vert
          ${PROJECT_SOURCE_DIR}/shaders/aurora.frag)
add_test(NAME tst_screens COMMAND tst_screens)
set_tests_properties(tst_screens PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# A story's article (ArticleReader): the function's answer shaped for the
# News screen, asked once per story against a fake Supabase, and the open
# story at each panel size.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-article
    Theme.qml Glass.qml components/Lens.qml components/Icon.qml components/IconButton.qml components/ChipRow.qml
    components/Tag.qml components/Reveal.qml components/FocusFlickable.qml components/QrPanel.qml
    components/EmptyState.qml components/ScreenHeader.qml components/StoryCard.qml components/MotionClock.qml
    screens/NewsScreen.qml)
qt_add_executable(tst_article tst_article.cpp FakeServer.h
    ../src/models/ArticleReader.h ../src/models/ArticleReader.cpp
    ../src/models/FeedStore.h     ../src/models/FeedStore.cpp
)
target_compile_options(tst_article PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_article PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-article")
target_link_libraries(tst_article PRIVATE mcfly-core mcfly-qr Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_resources(tst_article "demo_data_article"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/resources/demo/feed.json)
qt_add_shaders(tst_article "article_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/lens.frag)
add_test(NAME tst_article COMMAND tst_article)
set_tests_properties(tst_article PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# ScaledShader (src/graphics): the uniform block it fills from a shader's
# reflection and the properties of the same names.
qt_add_executable(tst_scaledshader tst_scaledshader.cpp)
target_compile_options(tst_scaledshader PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_scaledshader PRIVATE mcfly-graphics Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_scaledshader "scaledshader_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/arc.frag ${PROJECT_SOURCE_DIR}/shaders/arc.vert
          ${PROJECT_SOURCE_DIR}/shaders/gradienttile.frag ${PROJECT_SOURCE_DIR}/shaders/scaled.vert)
add_test(NAME tst_scaledshader COMMAND tst_scaledshader)
set_tests_properties(tst_scaledshader PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# A sky backdrop (Backdrop.qml): what its shader is fed through the dusk,
# against a stand-in DisplayController.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-backdrop
    Theme.qml components/Backdrop.qml)
qt_add_executable(tst_backdrop tst_backdrop.cpp)
target_compile_options(tst_backdrop PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_backdrop PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-backdrop")
target_link_libraries(tst_backdrop PRIVATE mcfly-graphics Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_backdrop "backdrop_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/arc.frag ${PROJECT_SOURCE_DIR}/shaders/arc.vert ${PROJECT_SOURCE_DIR}/shaders/ribbons.frag
          ${PROJECT_SOURCE_DIR}/shaders/dawn.frag ${PROJECT_SOURCE_DIR}/shaders/silk.frag
          ${PROJECT_SOURCE_DIR}/shaders/pillars.frag)
add_test(NAME tst_backdrop COMMAND tst_backdrop)
set_tests_properties(tst_backdrop PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The weather over a saver's backdrop (Weather.qml): what is built, how it
# moves, its colours, against a stand-in DisplayController with the real count.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-weather
    Theme.qml components/Weather.qml)
qt_add_executable(tst_weather tst_weather.cpp
    ../src/hardware/DisplayController.h
    ../src/hardware/DisplayController.cpp)
target_include_directories(tst_weather PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_weather PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_weather PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-weather")
target_link_libraries(tst_weather PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
add_test(NAME tst_weather COMMAND tst_weather)
set_tests_properties(tst_weather PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The assistant-first Home's opening lines, from empty, partial and full feeds.
qt_add_executable(tst_homeglance tst_homeglance.cpp
    ../src/models/HomeGlance.h ../src/models/HomeGlance.cpp
    ../src/models/FeedStore.h ../src/models/FeedStore.cpp)
target_include_directories(tst_homeglance PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_homeglance PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_homeglance PRIVATE mcfly-core Qt6::Gui Qt6::Test)
add_test(NAME tst_homeglance COMMAND tst_homeglance)
set_tests_properties(tst_homeglance PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The performance overlay's sampler (PerfMonitor): the /proc, /sys and
# vcgencmd text it reads on a Pi, from fixtures; that off it never samples;
# that on it counts a window's frames.
qt_add_executable(tst_perfmonitor tst_perfmonitor.cpp
    ../src/hardware/PerfMonitor.h ../src/hardware/PerfMonitor.cpp)
target_include_directories(tst_perfmonitor PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_perfmonitor PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_perfmonitor PRIVATE Qt6::Gui Qt6::Quick Qt6::Test)
add_test(NAME tst_perfmonitor COMMAND tst_perfmonitor)
set_tests_properties(tst_perfmonitor PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The settings sheet's tabs at each panel size, with the real controllers
# and the demo store.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-settings
    Theme.qml Glass.qml components/Lens.qml components/Icon.qml components/IconButton.qml
    components/PillButton.qml components/Toggle.qml components/FocusFlickable.qml components/QrPanel.qml
    components/TabStrip.qml screens/SettingsSheet.qml)
qt_add_executable(tst_settings tst_settings.cpp
    ../src/models/FeedStore.h  ../src/models/FeedStore.cpp
    ../src/models/Assistant.h  ../src/models/Assistant.cpp
    ../src/hardware/DisplayController.h ../src/hardware/DisplayController.cpp
    ../src/hardware/SystemController.h ../src/hardware/SystemController.cpp
    ../src/hardware/PerfMonitor.h ../src/hardware/PerfMonitor.cpp)
target_include_directories(tst_settings PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_settings PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_settings PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-settings")
target_link_libraries(tst_settings PRIVATE mcfly-core mcfly-qr Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_resources(tst_settings "demo_data_settings"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/resources/demo/feed.json)
qt_add_shaders(tst_settings "settings_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/lens.frag)
add_test(NAME tst_settings COMMAND tst_settings)
set_tests_properties(tst_settings PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# A stop (SIGTERM, SIGINT) reaches the event loop as a quit request, even
# when a handler like eglfs's, which exits 1 at once, was installed first.
qt_add_executable(tst_stopsignals tst_stopsignals.cpp
    ../src/hardware/StopSignals.h ../src/hardware/StopSignals.cpp)
target_include_directories(tst_stopsignals PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_stopsignals PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_stopsignals PRIVATE Qt6::Test)
add_test(NAME tst_stopsignals COMMAND tst_stopsignals)

# The settings bridge with a real DisplayController (no store, assistant or voice).
qt_add_executable(tst_settingsbridge tst_settingsbridge.cpp
    ../src/models/SettingsBridge.h ../src/models/SettingsBridge.cpp
    ../src/models/FeedStore.h ../src/models/FeedStore.cpp
    ../src/models/Assistant.h ../src/models/Assistant.cpp
    ../src/hardware/DisplayController.h ../src/hardware/DisplayController.cpp)
target_include_directories(tst_settingsbridge PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_settingsbridge PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_settingsbridge PRIVATE mcfly-core Qt6::Gui Qt6::Test)
add_test(NAME tst_settingsbridge COMMAND tst_settingsbridge)
set_tests_properties(tst_settingsbridge PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# ChipRow's chips: a tap within a touch target's height of a chip picks it,
# one between two chips neither, at the chip heights the screens use.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-chips
    Theme.qml Glass.qml components/Lens.qml components/ChipRow.qml)
qt_add_executable(tst_chips tst_chips.cpp)
target_compile_options(tst_chips PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_chips PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-chips")
target_link_libraries(tst_chips PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_chips "chips_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/lens.frag)
add_test(NAME tst_chips COMMAND tst_chips)
set_tests_properties(tst_chips PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The Games tab: GamesScreen.qml and every game, with the real theme. They are
# copied into a module directory laid out like the app's resources
# (qrc:/McFly/...), so the relative paths between them are the app's.
set(games_root ${CMAKE_CURRENT_BINARY_DIR}/games-qml/McFly)
set(games_qmldir "module McFly\n")
foreach(file qml/Theme.qml qml/Glass.qml qml/components/Lens.qml qml/components/Icon.qml
             qml/components/IconButton.qml qml/components/PillButton.qml qml/components/Tag.qml
             qml/components/SegmentedControl.qml qml/components/ScreenHeader.qml qml/components/Reveal.qml
             qml/components/FocusFlickable.qml qml/components/ChipRow.qml qml/games/ScoopTreat.qml
             qml/games/ScoopCrew.qml qml/games/ScoopAwning.qml)
    configure_file(${PROJECT_SOURCE_DIR}/${file} ${games_root}/${file} COPYONLY)
    get_filename_component(type ${file} NAME_WE)
    if(type STREQUAL "Theme" OR type STREQUAL "Glass")
        string(APPEND games_qmldir "singleton ")
    endif()
    string(APPEND games_qmldir "${type} 1.0 ${file}\n")
endforeach()
file(WRITE ${games_root}/qmldir "${games_qmldir}")
file(GLOB_RECURSE games_files RELATIVE ${PROJECT_SOURCE_DIR} CONFIGURE_DEPENDS
    ${PROJECT_SOURCE_DIR}/games/* ${PROJECT_SOURCE_DIR}/qml/games/*)
list(FILTER games_files EXCLUDE REGEX "__pycache__|\\.pyc$")
foreach(file ${games_files} qml/screens/GamesScreen.qml)
    configure_file(${PROJECT_SOURCE_DIR}/${file} ${games_root}/${file} COPYONLY)
endforeach()

qt_add_executable(tst_games tst_games.cpp
    ${PROJECT_SOURCE_DIR}/src/games/FourInARowEngine.h ${PROJECT_SOURCE_DIR}/src/games/FourInARowEngine.cpp)
target_include_directories(tst_games PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_games PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_games PRIVATE MCFLY_GAMES_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/games-qml")
target_link_libraries(tst_games PRIVATE mcfly-penguins mcfly-colors Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_games "games_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/lens.frag)
add_test(NAME tst_games COMMAND tst_games)
set_tests_properties(tst_games PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")
