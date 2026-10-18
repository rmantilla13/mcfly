// Rush Hour board logic by Michael Fogleman, https://github.com/fogleman/rush
// The Piece, Move and Board types of web/app.js at commit 3e3b8396
// (display/games/traffic/rush.js), in Swift.
//
// Copyright (C) 2018 Michael Fogleman
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// A Rush Hour board. A board is a 36-letter string read row by row: "o" is
/// an empty square, "x" a wall, and each other letter one car or truck, with
/// "A" the red car that has to leave through the exit on the right of its row.
public struct RushBoard: Sendable, Equatable {
    public struct Piece: Sendable, Equatable {
        public var position: Int
        public var size: Int
        public var stride: Int
        public var fixed: Bool { size == 1 }

        mutating func move(_ steps: Int) { position += stride * steps }
    }

    public struct Move: Sendable, Equatable, Hashable {
        public var piece: Int
        public var steps: Int
        public init(piece: Int, steps: Int) { self.piece = piece; self.steps = steps }
    }

    public enum Problem: Error { case empty, notSquare, tooShort, badShape }

    public private(set) var pieces: [Piece] = []
    public let size: Int
    public let primaryRow: Int

    public init(_ desc: String) throws {
        let chars = Array(desc)
        // determine board size
        size = Int(Double(chars.count).squareRoot())
        guard size > 0 else { throw Problem.empty }
        guard size * size == chars.count else { throw Problem.notSquare }

        // parse string
        var positions: [Character: [Int]] = [:]
        for (i, label) in chars.enumerated() { positions[label, default: []].append(i) }

        // add pieces, in label order
        for label in positions.keys.sorted() where label != "." && label != "o" && label != "x" {
            let ps = positions[label]!
            guard ps.count >= 2 else { throw Problem.tooShort }
            let stride = ps[1] - ps[0]
            guard stride == 1 || stride == size else { throw Problem.badShape }
            for i in 2..<ps.count where ps[i] - ps[i - 1] != stride { throw Problem.badShape }
            pieces.append(Piece(position: ps[0], size: ps.count, stride: stride))
        }
        // add walls
        for p in positions["x"] ?? [] { pieces.append(Piece(position: p, size: 1, stride: 1)) }

        primaryRow = pieces.isEmpty ? 0 : pieces[0].position / size
    }

    public mutating func doMove(_ move: Move) { pieces[move.piece].move(move.steps) }
    public mutating func undoMove(_ move: Move) { pieces[move.piece].move(-move.steps) }

    public var isSolved: Bool {
        guard let piece = pieces.first else { return false }
        return piece.position % size + piece.size == size
    }

    public func pieceAt(_ index: Int) -> Int? {
        for (i, piece) in pieces.enumerated() {
            var p = piece.position
            for _ in 0..<piece.size {
                if p == index { return i }
                p += piece.stride
            }
        }
        return nil
    }

    public func isOccupied(_ index: Int) -> Bool { pieceAt(index) != nil }

    public var moves: [Move] {
        var moves: [Move] = []
        for (i, piece) in pieces.enumerated() where !piece.fixed {
            let line = piece.stride == 1 ? piece.position % size : piece.position / size
            let reverseSteps = -line
            let forwardSteps = size - piece.size - line
            var idx = piece.position - piece.stride
            var steps = -1
            while steps >= reverseSteps {
                if isOccupied(idx) { break }
                moves.append(Move(piece: i, steps: steps))
                idx -= piece.stride
                steps -= 1
            }
            idx = piece.position + piece.size * piece.stride
            steps = 1
            while steps <= forwardSteps {
                if isOccupied(idx) { break }
                moves.append(Move(piece: i, steps: steps))
                idx += piece.stride
                steps += 1
            }
        }
        return moves
    }
}

/// Traffic Jam: the display's game (display/qml/games/TrafficJam.qml) on
/// Rush Hour's board. A slide only lands where `moves` allows it; the level
/// and each level's fewest moves are remembered by the app.
public struct TrafficJam: Sendable {
    /// The levels, easiest first: a board and the fewest moves that solve it
    /// (display/games/traffic/puzzles.js, made by make-puzzles.py).
    public static let levels: [(board: String, par: Int)] = [
        ("BooCCoBDDoEFAAooEFGGooooHooIIoHJJKKo", 4),
        ("BCoDDoBCEEFGAAooFGHHooooIJoKKoIJLLoo", 4),
        ("BCooDDBCooEEAAooFGHIIoFGHJJooKLLMMoK", 5),
        ("oBBCCoDDEEFGAAooFGHooIIoHooJJoKKLLoo", 5),
        ("BCDDooBCoEFGAAoEFGHooIIoHoJJooKKLLoo", 6),
        ("BCoDDoBCEFGHAAEFGHoIoJJooIooooKKoooo", 7),
        ("BoCCDDBEEoFGAAooFGoooHHIooJJJIKKoooo", 7),
        ("BCDEEEBCDFGGBAAFHIooooHIoooooJKKoooJ", 8),
        ("BoCCDDBooEFFAAoEGHooIIGHooJJoKLLMMoK", 9),
        ("ooBBooooCDDEAACFGEoHHFGooIIJJoKKoooo", 9),
        ("oBBCCoooDDEoAAoFEoGooFHHGIIJJKLLoooK", 10),
        ("BCDDEFBCGGEFHAAIoJHoKIoJooKLLoMMoooo", 11),
        ("oooBCCoDDBEFAAooEFGHHoEIGoJKKILLJooo", 12),
        ("oBCCDooBEFDGAAEFoGHoooIoHJJoIoKKoooo", 13),
        ("oBoCCCoBDDEEAAFoooGGFHoIJKKHoIJLLooo", 14),
        ("BCCDooBEEDoFAAGooFoHGIIooHJJKKLLoooo", 15),
        ("BCCDDoBEEFGGAAHFooIIHoJKoLMMJKoLNNoo", 16),
        ("oBBoCoooDoCEFGDAAEFGHHHEoooIJJKKoIoo", 17),
        ("BBoCDEFGoCDEFGAADoHHIoooJoIKKoJLLooo", 18),
        ("BBCooDEFCGGDEFAAHIJJoKHIoooKLoMMooLo", 19),
        ("BBCCCooooDEEAAoDFGHIIIFGHoJoKKLLJooo", 20),
        ("BBCCDEFFGGDEAAHooIooHJJIKooLMMKNNLoo", 21),
        ("BBBCDEFFGCDEAAGoooooHooooIHJJooIKKLL", 22),
        ("BooCDDBooCEFBoAAEFGGHoEIooHJJIKKLLoo", 23),
        ("BooCDDBEECoFoGoAAFoGHHIJKKLoIJooLMMJ", 24),
        ("oBBoCoDDEECoFAAGCoFoHGIIooHJJKLLoooK", 25),
        ("ooBCCCDoBEEFDAAGoFHIoGJJHIKKLoMMooLo", 26),
        ("BCCDDEBoFGGEAAFHooIJoHKKIJLLMoNNooMo", 27),
        ("BBBoCDoEFoCDoEFAAGHHFooGIooJKKILLJoo", 28),
        ("BCCDooBEFDGGoEFAAHIIJooHKKJooLMMNNoL", 29),
        ("BCCCDEBooFDEAAGFDoHHGIoooooIJJoKKooo", 30),
        ("BCCDoEBFoDGEBFAAGEHHIJGoooIJKKoLLMMo", 32),
        ("BCDDEEBCoFGoBAAFGHIIJoGHooJKKooLLMMo", 33),
        ("ooBCDDEoBCFGEAAoFGHHIIFJoKLLLJoKMMMo", 33),
        ("BBoCDDEooCFFEAACoGHIJKKGHIJoLMNNNoLM", 34),
        ("BoCCCDBoEFGDAAEFGHIIoJGHoooJKKoLLMMo", 36),
        ("oBCCDDoBEEEFAAGHoFooGHIIJoKKLMJNNNLM", 37),
        ("ooBBBoCDDEFGCAAEFGHIJJFKHILMMKNNLooo", 38),
        ("BBBCDDooECFFAAECoGHIIJJGHoKKLoMMooLo", 38),
        ("oBBBCDEEoFCDAAoFGHIJJKGHIoLKMMNNLooo", 41),
    ]

    public enum Band: Int, Sendable, CaseIterable {
        case beginner, intermediate, advanced, expert

        public var name: String {
            switch self {
            case .beginner: return "Beginner"
            case .intermediate: return "Intermediate"
            case .advanced: return "Advanced"
            case .expert: return "Expert"
            }
        }

        /// The band a level's fewest moves puts it in.
        public init(par: Int) {
            self = par <= 8 ? .beginner : par <= 16 ? .intermediate : par <= 25 ? .advanced : .expert
        }
    }

    /// Three stars for the fewest possible moves, two for close to it.
    public static func stars(moves: Int, par: Int) -> Int {
        moves <= par ? 3 : moves <= par + max(2, Int((Double(par) / 2).rounded(.up))) ? 2 : 1
    }

    public private(set) var level: Int
    public private(set) var board: RushBoard
    public private(set) var undoStack: [RushBoard.Move] = []
    public private(set) var solved = false

    public init(level: Int = 0) {
        let index = max(0, min(Self.levels.count - 1, level))
        self.level = index
        // The levels are checked by the tests.
        board = try! RushBoard(Self.levels[index].board) // swiftlint:disable:this force_try
    }

    public var par: Int { Self.levels[level].par }
    public var moves: Int { undoStack.count }

    /// Slides piece `index` by `steps` squares (negative: left or up) if the
    /// board allows it. Drags end here.
    @discardableResult
    public mutating func slide(_ index: Int, _ steps: Int) -> Bool {
        guard !solved, steps != 0, board.moves.contains(RushBoard.Move(piece: index, steps: steps)) else { return false }
        let move = RushBoard.Move(piece: index, steps: steps)
        board.doMove(move)
        undoStack.append(move)
        if board.isSolved { solved = true }
        return true
    }

    public mutating func undo() {
        guard !solved, let move = undoStack.popLast() else { return }
        board.undoMove(move)
    }

    /// How far piece `index` can slide right now: fewest and most steps.
    public func range(_ index: Int) -> ClosedRange<Int> {
        var lo = 0, hi = 0
        for m in board.moves where m.piece == index {
            lo = min(lo, m.steps)
            hi = max(hi, m.steps)
        }
        return lo...hi
    }
}
