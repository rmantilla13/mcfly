import Foundation

/// The Games list: the display's catalog (display/qml/screens/GamesScreen.qml),
/// with each game's how to play and its credit, word for word. Same Game and
/// Maroon in Trouble, the Qt demos, aren't in the app yet.
public enum GameID: String, Sendable, CaseIterable, Identifiable {
    case trafficJam, ticTacToe, fourInARow, game2048, scoopShop, penguinMarch

    public var id: Self { self }

    public var title: String {
        switch self {
        case .trafficJam: return "Traffic Jam"
        case .ticTacToe: return "Tic-tac-toe"
        case .fourInARow: return "Four in a Row"
        case .game2048: return "2048"
        case .scoopShop: return "Scoop Shop"
        case .penguinMarch: return "Penguin March"
        }
    }

    public var tagline: String {
        switch self {
        case .trafficJam: return "Slide the cars to get the red one out."
        case .ticTacToe: return "Three in a row wins."
        case .fourInARow: return "Drop the discs, line up four."
        case .game2048: return "Slide and join the tiles to reach 2048."
        case .scoopShop: return "Serve every order before they give up."
        case .penguinMarch: return "Get the penguins home to the igloo."
        }
    }

    public var howTo: String {
        switch self {
        case .trafficJam:
            return "Drag the cars and trucks along their lanes. Cars only go forward and back. Clear a path so the red car can drive out of the exit on the right. 40 levels, from beginner to expert."
        case .ticTacToe:
            return "Take turns tapping a square. The first to get three in a row, across, down or corner to corner, wins. Play someone at the screen, or play McFly: Easy is beatable, Hard never loses."
        case .fourInARow:
            return "Take turns tapping a column to drop a disc into it. The first to line up four, across, down or corner to corner, wins. Play someone at the screen, or play McFly: Easy is beatable, Hard looks several moves ahead."
        case .game2048:
            return "Swipe up, down, left or right to slide every tile. Two tiles with the same number join into one. Make a 2048 tile to win, then keep going."
        case .scoopShop:
            return "Pick who works the counter: Pip the penguin or Lotl the axolotl. Each customer's ticket shows their order: a cone or a cup, the scoops from the bottom up, and any toppings. Tap the pieces to build it, then tap the customer to hand it over. Right and quick scores more. A wrong order, or a customer who runs out of patience, costs a heart; lose three and the shop closes. Every five served it gets busier."
        case .penguinMarch:
            return "Penguins drop in and keep walking, turning at walls, and a long fall is the end of one. Pick a skill, then tap a penguin: Block turns the others back, Dig goes down, Bash goes through a wall, Build lays steps and Float opens an umbrella. Get enough of them into the igloo to win."
        }
    }

    public var players: String {
        switch self {
        case .ticTacToe, .fourInARow: return "1–2 players"
        default: return "1 player"
        }
    }

    /// Where it comes from, shown under how to play.
    public var credit: String {
        switch self {
        case .trafficJam: return "Rush Hour board logic by Michael Fogleman (MIT License). Levels made for McFly."
        case .ticTacToe, .fourInARow, .penguinMarch: return "Made for McFly."
        case .game2048: return "2048 by Gabriele Cirulli. MIT License."
        case .scoopShop: return "Made for McFly, Pip and Lotl too."
        }
    }

    /// The licence the game's code came under, in full, for the games that
    /// are ports of someone else's (the notice has to travel with the copy).
    public var licence: String? {
        switch self {
        case .game2048: return Self.mit("Copyright (c) 2014 Gabriele Cirulli")
        case .trafficJam: return Self.mit("Copyright (C) 2018 Michael Fogleman")
        default: return nil
        }
    }

    private static func mit(_ copyright: String) -> String {
        """
        The MIT License (MIT)

        \(copyright)

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in \
        all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN \
        THE SOFTWARE.
        """
    }

    /// Runs on a clock, so it pauses while how to play covers it.
    public var timed: Bool { self == .scoopShop || self == .penguinMarch }
}
