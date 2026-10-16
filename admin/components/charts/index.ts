// Chart primitives drawn with SVG and CSS (no charting library). Sparkline,
// RingGauge, BarStrip and StatusDot render on the server with no client
// JavaScript; AreaChart is a client component for its crosshair. Every
// prop is plain data, so server pages can pass them straight through.
export { AreaChart, type AreaPoint } from "./AreaChart";
export { BarStrip, type BarStripBar, type BarStripSeries } from "./BarStrip";
export { RingGauge } from "./RingGauge";
export { Sparkline } from "./Sparkline";
export { StatusDot, type StatusState } from "./StatusDot";
export type { ChartTone } from "./tone";
