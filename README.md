# AIP Project Lab – Wizard-of-Oz Restaurant Dialogue

TUM Project Lab Audio Information Processing (WS 2026/27).
A Wizard-of-Oz setup where a MetaHuman avatar in Unreal Engine 5 plays a waiter, and the
experimenter controls its responses in real time from a MATLAB interface.

## Repository structure

| Path | Content |
|---|---|
| `woz_interface/` | MATLAB Wizard-of-Oz control interface, waiter audio clips, dialogue tree and exported diagram |
| `restaurant_ordering_branching_dialogue.drawio-2` | Dialogue diagram (draw.io) |

## MATLAB interface

Setup, usage, UE5 protocol and logging are documented in
**[woz_interface/README.md](woz_interface/README.md)**.

## Dialogue diagram

The dialogue diagram is maintained by Yunye in draw.io; the latest version is on the `yunye` branch.
The version used for the MATLAB interface, with its small changes, is exported as SVG in
[`woz_interface/diagram/`](woz_interface/diagram/). See the "Dialogue diagram" section of the
interface README for the differences.
