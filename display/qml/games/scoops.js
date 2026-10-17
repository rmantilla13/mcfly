// Scoop Shop's rules, kept apart from the drawing so tests can check them:
// what each customer orders, how long they wait, what a delivery scores,
// and how the shop gets busier.
.pragma library

var BASES = ["cone", "cup"]
var FLAVOURS = ["vanilla", "chocolate", "strawberry", "mint"]
var TOPPINGS = ["sprinkles", "cherry", "wafer"]
var MAX_SCOOPS = 3
var MAX_LEVEL = 10
// Customers served to reach the next level.
var PER_LEVEL = 5
var HEARTS = 3
// Seats at the counter, at most (the layout has room for this many).
var MAX_SEATS = 4

// A small seeded generator (mulberry32), so a test can replay a shift:
// next() steps its state, unit() turns a state into a number in [0, 1).
function next(state) {
    return (state + 0x6D2B79F5) >>> 0
}
function unit(state) {
    var t = state >>> 0
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}
function random(seed) {
    var state = seed >>> 0
    return function () {
        state = next(state)
        return unit(state)
    }
}

function level(served) {
    return Math.min(MAX_LEVEL, 1 + Math.floor(served / PER_LEVEL))
}

// What a level asks for. Times are in milliseconds.
function rules(lv) {
    lv = Math.max(1, Math.min(MAX_LEVEL, lv))
    return {
        seats: lv < 3 ? 2 : lv < 5 ? 3 : 4,
        minScoops: lv < 5 ? 1 : 2,
        maxScoops: lv < 2 ? 1 : lv < 4 ? 2 : 3,
        minToppings: lv < 7 ? 0 : 1,
        maxToppings: lv < 2 ? 0 : lv < 4 ? 1 : 2,
        // How long a customer waits: a little for being there, more for
        // each thing on the order, both shorter as the shop gets busy.
        wait: Math.max(10000, 24000 - 1600 * (lv - 1)),
        perItem: Math.max(1600, 3000 - 200 * (lv - 1)),
        // Time between customers arriving.
        arrival: Math.max(2500, 7000 - 500 * (lv - 1))
    }
}

function pick(rand, list) {
    return list[Math.floor(rand() * list.length)]
}
function between(rand, lo, hi) {
    return lo + Math.floor(rand() * (hi - lo + 1))
}

// An order for this level: { base, scoops (bottom to top), toppings }.
function makeOrder(lv, rand) {
    var r = rules(lv)
    var scoops = []
    var n = between(rand, r.minScoops, r.maxScoops)
    for (var i = 0; i < n; ++i)
        scoops.push(pick(rand, FLAVOURS))
    var left = TOPPINGS.slice()
    var toppings = []
    var t = between(rand, r.minToppings, r.maxToppings)
    for (var j = 0; j < t; ++j)
        toppings.push(left.splice(Math.floor(rand() * left.length), 1)[0])
    // Toppings in the menu's order: they all go on top, so it doesn't matter.
    toppings.sort(function (a, b) { return TOPPINGS.indexOf(a) - TOPPINGS.indexOf(b) })
    return { base: pick(rand, BASES), scoops: scoops, toppings: toppings }
}

// The base, each scoop and each topping.
function items(order) {
    return (order.base ? 1 : 0) + order.scoops.length + order.toppings.length
}

function patience(order, lv) {
    var r = rules(lv)
    return r.wait + r.perItem * items(order)
}

// Right when the base matches, the scoops match in order from the bottom
// up, and the toppings match in any order.
function matches(order, build) {
    if (!build || order.base !== build.base || order.scoops.length !== build.scoops.length
            || order.toppings.length !== build.toppings.length)
        return false
    for (var i = 0; i < order.scoops.length; ++i) {
        if (order.scoops[i] !== build.scoops[i])
            return false
    }
    for (var j = 0; j < order.toppings.length; ++j) {
        if (build.toppings.indexOf(order.toppings[j]) < 0)
            return false
    }
    return true
}

// Ten a thing on the order, and up to as much again for speed: `left` is
// the share of the customer's patience still left, 0 to 1.
function points(order, left) {
    var n = items(order)
    return 10 * n + Math.round(10 * n * Math.max(0, Math.min(1, left)))
}
