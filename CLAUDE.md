# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Reimplementation of the Texas Instruments TMS34010 Graphics System Processor in SystemVerilog. The TMS34010 is a 32-bit general-purpose CPU with graphics-oriented instructions (PIXBLT, FILL, LINE, etc.), a bit-addressable memory model, and an integrated CRT controller — any RTL here should be evaluated against the original device's documented behavior, not a generic CPU model.

## Repository state

The repo is pre-source: only `README.md` and `LICENSE` exist. There is no RTL, testbench, simulator config, or build system yet. Before assuming any toolchain, file layout, or coding convention, check the working tree — most things future-you would expect to find are not here yet. When adding the first files, ask the user about simulator choice (Verilator / Icarus / Questa / VCS / Vivado), lint tool, and whether they want a formal verification flow, rather than picking unilaterally.

## When updating this file

Replace this "Repository state" section as soon as real structure lands. The useful things to document then are the parts a fresh Claude instance can't infer from the tree: bit-addressed memory conventions, how the instruction-set decoder is partitioned, testbench harness entry points, and any cycle-accuracy goals vs. the original silicon.
