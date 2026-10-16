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
        if(type STREQUAL "Theme")
            string(APPEND qmldir "singleton ")
        endif()
        string(APPEND qmldir "${type} 1.0 ${file}\n")
    endforeach()
    file(WRITE ${dir}/McFly/qmldir "${qmldir}")
endfunction()

# The wake-word card (QuickAnswer.qml) with the real assistant and voice client.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml
    Theme.qml components/Icon.qml components/IconButton.qml components/PillButton.qml
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
    FILES ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.frag)
add_test(NAME tst_quickanswer COMMAND tst_quickanswer)
set_tests_properties(tst_quickanswer PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The wall dialogs' shell (FormDialog.qml) under a Layer, the way Main.qml
# stacks the on-screen keyboard over dialogs; and closing when the display
# goes idle.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-dialogs
    Theme.qml components/PillButton.qml components/FormField.qml components/FocusFlickable.qml
    components/FormDialog.qml components/Layer.qml)
qt_add_executable(tst_dialogs tst_dialogs.cpp)
target_compile_options(tst_dialogs PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_dialogs PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-dialogs")
target_link_libraries(tst_dialogs PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
add_test(NAME tst_dialogs COMMAND tst_dialogs)
set_tests_properties(tst_dialogs PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# Motion: the palette's fade lengths, GradientTile's drift and SpectrumGlow's
# idle cap, against a stand-in DisplayController.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-motion
    Theme.qml components/GradientTile.qml components/SpectrumGlow.qml)
qt_add_executable(tst_motion tst_motion.cpp)
target_compile_options(tst_motion PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_motion PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-motion")
target_link_libraries(tst_motion PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_motion "motion_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/gradienttile.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.frag)
add_test(NAME tst_motion COMMAND tst_motion)
set_tests_properties(tst_motion PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The screens' motion and layouts (Home, Boards, Briefs) against the real
# store at a fixed time of day: the reveal, the insight line, Home's
# countdown and now marker, board tiles from boardLayout, the Briefs outline,
# the nav's thinking ring.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-screens
    Theme.qml components/Icon.qml components/IconButton.qml components/PillButton.qml
    components/SpectrumGlow.qml components/GradientTile.qml components/Sparkline.qml
    components/Ring.qml components/StatusDot.qml components/Reveal.qml components/InsightLine.qml
    components/HealthStrip.qml components/SuggestionChips.qml components/FocusFlickable.qml
    components/QrPanel.qml components/EmptyState.qml components/ScreenHeader.qml components/ChipRow.qml
    components/MasterDetail.qml components/Tag.qml components/NavRail.qml
    screens/HomeScreen.qml screens/DashboardsScreen.qml screens/BriefsScreen.qml)
qt_add_executable(tst_screens tst_screens.cpp
    ../src/models/FeedStore.h  ../src/models/FeedStore.cpp
    ../src/models/Assistant.h  ../src/models/Assistant.cpp
)
target_compile_options(tst_screens PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_screens PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-screens")
target_link_libraries(tst_screens PRIVATE mcfly-core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_resources(tst_screens "demo_data_screens"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/resources/demo/feed.json)
qt_add_shaders(tst_screens "screens_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/gradienttile.frag ${PROJECT_SOURCE_DIR}/shaders/spectrumglow.frag)
add_test(NAME tst_screens COMMAND tst_screens)
set_tests_properties(tst_screens PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# A sky backdrop (Backdrop.qml): what its shader is fed through the dusk,
# against a stand-in DisplayController.
mcfly_test_qml_module(${CMAKE_CURRENT_BINARY_DIR}/qml-backdrop
    Theme.qml components/Backdrop.qml)
qt_add_executable(tst_backdrop tst_backdrop.cpp)
target_compile_options(tst_backdrop PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_backdrop PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-backdrop")
target_link_libraries(tst_backdrop PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
qt_add_shaders(tst_backdrop "backdrop_shaders"
    PREFIX /McFly
    BASE ${PROJECT_SOURCE_DIR}
    FILES ${PROJECT_SOURCE_DIR}/shaders/arc.frag ${PROJECT_SOURCE_DIR}/shaders/ribbons.frag
          ${PROJECT_SOURCE_DIR}/shaders/dawn.frag ${PROJECT_SOURCE_DIR}/shaders/silk.frag
          ${PROJECT_SOURCE_DIR}/shaders/pillars.frag)
add_test(NAME tst_backdrop COMMAND tst_backdrop)
set_tests_properties(tst_backdrop PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")

# The assistant-first Home's opening lines, from empty, partial and full feeds.
qt_add_executable(tst_homeglance tst_homeglance.cpp
    ../src/models/HomeGlance.h ../src/models/HomeGlance.cpp
    ../src/models/FeedStore.h ../src/models/FeedStore.cpp)
target_include_directories(tst_homeglance PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_compile_options(tst_homeglance PRIVATE ${MCFLY_WARNINGS})
target_link_libraries(tst_homeglance PRIVATE mcfly-core Qt6::Gui Qt6::Test)
add_test(NAME tst_homeglance COMMAND tst_homeglance)
set_tests_properties(tst_homeglance PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

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
    Theme.qml components/ChipRow.qml)
qt_add_executable(tst_chips tst_chips.cpp)
target_compile_options(tst_chips PRIVATE ${MCFLY_WARNINGS})
target_compile_definitions(tst_chips PRIVATE MCFLY_TEST_QML_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml-chips")
target_link_libraries(tst_chips PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
add_test(NAME tst_chips COMMAND tst_chips)
set_tests_properties(tst_chips PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")
