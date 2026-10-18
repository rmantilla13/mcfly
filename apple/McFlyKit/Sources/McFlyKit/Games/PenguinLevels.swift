import Foundation

// Penguin March's 16 levels, the display's (display/src/games/PenguinLevels.cpp):
// each brings in one skill, then they're combined. Every level carries a
// recorded solution, replayed by PenguinMarchTests to prove it can be won.
extension PenguinLevel {
    public static let all: [PenguinLevel] = make()

    private static func at(_ id: Int, _ skill: PenguinSkill, _ x: Int, _ y: Int? = nil) -> PenguinStep {
        PenguinStep(id: id, skill: skill, atX: x, atY: y)
    }

    private static func with(_ level: PenguinLevel, _ change: (inout PenguinLevel) -> Void) -> PenguinLevel {
        var l = level
        change(&l)
        return l
    }

    // swiftlint:disable:next function_body_length
    private static func make() -> [PenguinLevel] {
        typealias S = PenguinShape
        var all: [PenguinLevel] = []

        // 1. Dig: out of a pen through its floor.
        all.append(with(PenguinLevel(name: "Straight Down",
                                     hint: "Diggers dig straight down through snow and ice. Tap Dig, then tap a penguin.",
                                     total: 10, need: 8)) { l in
            l.entrance = PenguinPoint(70, 32)
            l.exit = PenguinPoint(320, 139)
            l.skills[PenguinSkill.dig.rawValue] = 2
            l.shapes = [S.rect(20, 70, 200, 20), S.rect(20, 40, 10, 30), S.rect(210, 40, 10, 30),
                        S.rect(0, 140, 400, 44), S.ellipse(60, 132, 70, 20), S.ellipse(250, 134, 40, 14)]
            l.solution = [at(0, .dig, 120)]
        })
        // 2. Float: off a cliff too high to survive.
        all.append(with(PenguinLevel(name: "Umbrellas Up",
                                     hint: "A fall this long needs an umbrella. Give each penguin Float before it steps off.",
                                     total: 6, need: 5)) { l in
            l.rate = 50
            l.entrance = PenguinPoint(40, 36)
            l.exit = PenguinPoint(330, 167)
            l.skills[PenguinSkill.float.rawValue] = 6
            l.shapes = [S.rect(0, 64, 150, 120), S.poly([(150, 64), (158, 80), (150, 184)]), S.rect(150, 168, 250, 16),
                        S.ellipse(250, 160, 50, 16)]
            l.solution = (0..<6).map { at($0, .float, 100) }
        })
        // 3. Block: they're walking the wrong way.
        all.append(with(PenguinLevel(name: "Hold the Line",
                                     hint: "A blocker stands still and turns the others around. These are headed for the water.",
                                     total: 10, need: 9)) { l in
            l.rate = 35
            l.entrance = PenguinPoint(200, 44)
            l.exit = PenguinPoint(60, 103)
            l.skills[PenguinSkill.block.rawValue] = 2
            l.shapes = [S.rect(0, 104, 270, 80), S.poly([(270, 104), (276, 120), (270, 184)])]
            l.water = [PenguinRect(270, 150, 130, 34)]
            l.solution = [at(0, .block, 250)]
        })
        // 4. Build: a bridge over water.
        all.append(with(PenguinLevel(name: "Mind the Gap",
                                     hint: "Builders lay a bridge of steps ahead of them. Start one at the edge.",
                                     total: 10, need: 9)) { l in
            l.entrance = PenguinPoint(50, 44)
            l.exit = PenguinPoint(340, 103)
            l.skills[PenguinSkill.build.rawValue] = 2
            l.shapes = [S.rect(0, 104, 150, 80), S.rect(190, 104, 210, 80)]
            l.water = [PenguinRect(150, 150, 40, 34)]
            l.solution = [at(0, .build, 145)]
        })
        // 5. Bash: through a wall.
        all.append(with(PenguinLevel(name: "Break Through",
                                     hint: "Bashers punch a tunnel straight through a wall.", total: 10, need: 9)) { l in
            l.entrance = PenguinPoint(60, 60)
            l.exit = PenguinPoint(330, 119)
            l.skills[PenguinSkill.bash.rawValue] = 2
            l.shapes = [S.rect(0, 120, 400, 64), S.poly([(170, 120), (174, 40), (206, 36), (210, 120)])]
            l.solution = [at(0, .bash, 165)]
        })
        // 6. Build twice: a cliff higher than one bridge.
        all.append(with(PenguinLevel(name: "Upstairs",
                                     hint: "One bridge won't reach the top. Give the builder Build again before it's done.",
                                     total: 10, need: 9)) { l in
            l.entrance = PenguinPoint(40, 80)
            l.exit = PenguinPoint(340, 95)
            l.skills[PenguinSkill.build.rawValue] = 3
            l.shapes = [S.rect(0, 140, 400, 44), S.rect(180, 96, 220, 44)]
            l.solution = [at(0, .build, 90), at(0, .build, 134)]
        })
        // 7. Block and dig: rock everywhere but one patch, behind them.
        all.append(with(PenguinLevel(name: "About Turn",
                                     hint: "Grey rock can't be dug. Turn them back, then dig through the ice.",
                                     total: 10, need: 8)) { l in
            l.rate = 25
            l.entrance = PenguinPoint(250, 50)
            l.exit = PenguinPoint(50, 159)
            l.skills[PenguinSkill.block.rawValue] = 1
            l.skills[PenguinSkill.dig.rawValue] = 1
            l.shapes = [S.rect(0, 90, 300, 24, .steel), S.rect(100, 90, 40, 24), S.rect(0, 160, 300, 24),
                        S.poly([(300, 160), (306, 172), (300, 184)])]
            l.water = [PenguinRect(300, 150, 100, 34)]
            l.solution = [at(0, .block, 285), at(1, .dig, 120)]
        })
        // 8. Bash, then build.
        all.append(with(PenguinLevel(name: "Tunnel and Bridge",
                                     hint: "Through the wall, then over the water.", total: 10, need: 9)) { l in
            l.entrance = PenguinPoint(40, 60)
            l.exit = PenguinPoint(350, 119)
            l.skills[PenguinSkill.bash.rawValue] = 1
            l.skills[PenguinSkill.build.rawValue] = 1
            l.shapes = [S.rect(0, 120, 230, 64), S.rect(110, 40, 30, 80), S.rect(270, 120, 130, 64)]
            l.water = [PenguinRect(230, 150, 40, 34)]
            l.solution = [at(0, .bash, 105), at(0, .build, 226)]
        })
        // 9. Dig, then bash: down out of a pen, out of a cellar.
        all.append(with(PenguinLevel(name: "Down and Out",
                                     hint: "Down through the floor, then out through the ice. Rock stops a basher too.",
                                     total: 10, need: 9)) { l in
            l.entrance = PenguinPoint(80, 34)
            l.exit = PenguinPoint(340, 139)
            l.skills[PenguinSkill.dig.rawValue] = 2
            l.skills[PenguinSkill.bash.rawValue] = 2
            l.shapes = [S.rect(0, 100, 400, 84, .steel), S.rect(0, 60, 30, 40, .steel),
                        S.rect(170, 60, 90, 40, .steel), S.rect(20, 24, 10, 36, .steel),
                        S.rect(170, 24, 10, 36, .steel), S.rect(30, 80, 140, 20),
                        S.rect(30, 100, 190, 40, .cut), S.rect(220, 100, 40, 40), S.rect(260, 50, 140, 90, .cut),
                        S.ellipse(300, 132, 40, 16)]
            l.solution = [at(0, .dig, 100), at(0, .bash, 215)]
        })
        // 10. Float, then build: down to an island, over to the shore.
        all.append(with(PenguinLevel(name: "Island Hop",
                                     hint: "Umbrellas down to the island, then a bridge to the shore.", total: 8, need: 6)) { l in
            l.entrance = PenguinPoint(40, 24)
            l.exit = PenguinPoint(350, 149)
            l.skills[PenguinSkill.float.rawValue] = 8
            l.skills[PenguinSkill.build.rawValue] = 2
            l.shapes = [S.rect(0, 50, 110, 134), S.poly([(110, 50), (116, 64), (110, 184)]), S.ellipse(112, 146, 60, 20),
                        S.rect(116, 150, 54, 34), S.rect(210, 150, 190, 34), S.ellipse(280, 142, 50, 16)]
            l.water = [PenguinRect(170, 156, 40, 28)]
            l.solution = (0..<8).map { at($0, .float, 80) } + [at(0, .build, 165)]
        })
        // 11. Two bridges: one over water, one up onto a ledge.
        all.append(with(PenguinLevel(name: "Two Bridges",
                                     hint: "Over the water, then up to the ledge. One builder can do both.",
                                     total: 10, need: 9)) { l in
            l.entrance = PenguinPoint(40, 60)
            l.exit = PenguinPoint(360, 95)
            l.skills[PenguinSkill.build.rawValue] = 3
            l.shapes = [S.rect(0, 120, 140, 64), S.rect(180, 120, 220, 64), S.rect(290, 96, 110, 24),
                        S.ellipse(60, 114, 40, 12)]
            l.water = [PenguinRect(140, 156, 40, 28)]
            l.solution = [at(0, .build, 136), at(0, .build, 240)]
        })
        // 12. Float, then bash: off a cliff into a walled basin.
        all.append(with(PenguinLevel(name: "Over the Edge",
                                     hint: "Umbrellas for the drop, then a way through the wall.", total: 8, need: 7)) { l in
            l.entrance = PenguinPoint(40, 30)
            l.exit = PenguinPoint(345, 159)
            l.skills[PenguinSkill.float.rawValue] = 8
            l.skills[PenguinSkill.bash.rawValue] = 2
            l.shapes = [S.rect(0, 56, 120, 128), S.rect(120, 160, 280, 24),
                        S.poly([(230, 160), (236, 64), (262, 70), (260, 160)]),
                        S.rect(0, 56, 120, 128), S.ellipse(150, 152, 50, 16)]
            l.solution = (0..<8).map { at($0, .float, 100) } + [at(0, .bash, 225)]
        })
        // 13. Dig, dig, bash.
        all.append(with(PenguinLevel(name: "Deep Freeze",
                                     hint: "Two floors down and one wall across.", total: 10, need: 8)) { l in
            l.entrance = PenguinPoint(60, 30)
            l.exit = PenguinPoint(370, 169)
            l.skills[PenguinSkill.dig.rawValue] = 2
            l.skills[PenguinSkill.bash.rawValue] = 1
            l.shapes = [S.rect(0, 60, 200, 20), S.rect(200, 20, 20, 60, .steel), S.rect(0, 120, 300, 20),
                        S.rect(220, 80, 20, 40, .steel), S.rect(0, 170, 400, 14), S.rect(300, 100, 30, 70),
                        S.ellipse(140, 164, 50, 12)]
            l.solution = [at(0, .dig, 100), at(0, .dig, 150), at(0, .bash, 295)]
        })
        // 14. Block, build, dig.
        all.append(with(PenguinLevel(name: "Crossroads",
                                     hint: "Turn them, bridge the pit, and dig down to the igloo.", total: 10, need: 8)) { l in
            l.entrance = PenguinPoint(300, 40)
            l.exit = PenguinPoint(40, 159)
            l.skills[PenguinSkill.block.rawValue] = 1
            l.skills[PenguinSkill.build.rawValue] = 1
            l.skills[PenguinSkill.dig.rawValue] = 1
            l.shapes = [S.rect(0, 90, 180, 30), S.rect(215, 90, 125, 30, .steel), S.rect(170, 120, 10, 40, .steel),
                        S.rect(0, 160, 180, 24), S.rect(180, 150, 35, 34, .steel),
                        S.poly([(340, 90), (346, 104), (340, 120)], .steel)]
            l.water = [PenguinRect(181, 140, 33, 10), PenguinRect(340, 150, 60, 34)]
            l.solution = [at(0, .block, 325), at(1, .build, 219), at(1, .dig, 80)]
        })
        // 15. Dig, bash, float: out of the ice cap, out of the cave, down the cliff.
        all.append(with(PenguinLevel(name: "The Glacier",
                                     hint: "Down through the ice cap, out of the cave, and umbrellas for the long way down.",
                                     total: 8, need: 6)) { l in
            l.entrance = PenguinPoint(60, 18)
            l.exit = PenguinPoint(360, 175)
            l.skills[PenguinSkill.dig.rawValue] = 1
            l.skills[PenguinSkill.bash.rawValue] = 1
            l.skills[PenguinSkill.float.rawValue] = 8
            l.shapes = [S.rect(20, 30, 180, 20), S.rect(10, 6, 10, 44, .steel), S.rect(200, 6, 10, 44, .steel),
                        S.rect(0, 100, 280, 20, .steel), S.rect(0, 120, 280, 64, .steel),
                        S.rect(250, 50, 30, 50), S.poly([(280, 100), (286, 112), (280, 184)], .steel),
                        S.rect(280, 176, 120, 8), S.ellipse(300, 170, 40, 12)]
            l.solution = [at(0, .dig, 110), at(0, .bash, 245)] + (0..<8).map { at($0, .float, 278) }
        })
        // 16. Everything: turn them, tunnel, bridge, and dig down to the igloo.
        all.append(with(PenguinLevel(name: "Grand March",
                                     hint: "All the way home: turn them, tunnel, bridge, and dig.", total: 12, need: 10)) { l in
            l.rate = 30
            l.entrance = PenguinPoint(220, 26)
            l.exit = PenguinPoint(360, 175)
            l.skills[PenguinSkill.block.rawValue] = 1
            l.skills[PenguinSkill.dig.rawValue] = 1
            l.skills[PenguinSkill.bash.rawValue] = 1
            l.skills[PenguinSkill.build.rawValue] = 1
            l.skills[PenguinSkill.float.rawValue] = 2
            l.shapes = [S.rect(120, 52, 160, 20), S.poly([(280, 52), (286, 62), (280, 72)]), S.rect(0, 110, 240, 20),
                        S.rect(180, 72, 20, 38), S.rect(280, 110, 120, 20), S.rect(280, 176, 120, 8),
                        S.rect(0, 130, 240, 54, .steel), S.rect(270, 130, 10, 54, .steel)]
            l.water = [PenguinRect(240, 160, 30, 24)]
            l.solution = [at(0, .block, 265), at(1, .bash, 175, 109), at(1, .build, 236), at(1, .dig, 320)]
        })
        return all
    }
}
