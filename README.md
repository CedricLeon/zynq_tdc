# ZYNQ Time-to-digital converter

## TODO
- [ ] Update the TCL script for the Zedboard evaluation Kit (instead of the Red pitaya)

## To Check
#### Physical mapping
*Critical warning*: "[Common 17-69] Command failed: 'M14' is not a valid site or package pin name. ["/localhome/leon_ce/dev/zynq_tdc/src/ports.xdc":15]"
- What pins are hardcoded in the design? By what should we change them? See Zedboard hardware User Guide
#### Clock frequency
- What is our clock frequency?
- If it's different than the paper, how many Taps do we need?
- the line length should allow for a delay longer than a clock cycle

#### Shared memory?
Each TDC has it's own BRAM, right?

## Detailed project explanation
This section holds my notes about the project. These are oversimplified and omit lots of details, I **strongly** advise to refer to the paper of the source files for detailed information. That said, the following notes provide a great overview of what happens where.
### Source files
#### utils
##### MyPkG.vhd
A package with a list of utils. E.g., `isPowerOf2()`
##### risingEdgeDetector.vhd
A simple file doing exactly what the title says.
##### sync.vhd
A 2 flip-flop synchronizer to be used with Clock Domain Crossing (CDC). It synchronizes an asynchronous signal to a target clock domain. It uses 2 flip-flops (The `FDCE` primitive) in series to reduce the chance of metastability.
#### main files
##### counter.vhd
*coarse counter*
A simple counter of clock cycles used for the coarse measurement. takes `clk` in and outputs a vector of bits of 24bits 9it's a generic parameter set in TDCchannel with the `COARSE_BITS` constant).
##### delayLine.vhd
*fine counter*
Implements the whole logic of the tapped Delay line (TDL), this is quite heavy, but here are the main points:
- The number of 'Taps' (of FFs) `NTaps` can be set, should be a multiple of 12, default: 48
- There is 3 ports in: `clk`, `hit` and `enable`. These are self-explanatory
- And 2 ports out: `thermo` and `valid`:
	- `thermo` stands for the thermometer code of the delay line, it corresponds to the concatenated output of all the taps (more specifically the `CARRYOUT`) (Detail: the VHDL code uses a `metaThermo` seemingly useless variable to avoid metastability.)
	- `valid` is the first bit of `thermo`, it ==seems== to indicate if the signal is valid (if we measured smth) or not
- the actual line is implemented using `CARRY4` primitives, each carry block represent 4 taps
##### adderTree.vhd
Defines the pipelined added tree used by the encoder. I won't go into the details, this is some pretty complex code coming from a Stackoverflow template. The main idea is to recursively add inputs together until there is only one input left, this is the final sum.
About the signals, it takes in a vector of inputs of a certain length `x_in`, and outputs there sum `y_out`. It also has 1 valid signal in and 1 out.
##### encoder.vhd
*interpretation of the TDL*
The encoder computes the number of 1s in the thermo code sent by the delay line. It uses LUTs and an adder tree for that.
- It takes in `thermo` the thermometer code and `validIn` from the TDL.
- And it outputs `ones`, the number of 1 in `thermo`, as well as, `validOut`
##### control.vhd
*FSM of the IP*
Defines the control unit for the TDC. It uses a Finite State Machine (FSM) to control the operation of the system.
- The entity takes as input the incoming `timestamp` (coarse and fine concatenated) `valid`.
- `trigger_in` and `trigger_out` are signals used to keep track of how many measurements have been made (closely linked to the internal variable `addr_cnt`), I believe these are only informative (i.e., for debugging) as the FSM goes to `RUN_DONE` by checking if `addr_cnt = ADDR_MAX`.

The FSM has 4 control signals; `run`, and `clr` the main ones. but also, `rdy` for the initialization and `full` acting as a flag for the BRAM.
The FSM has 6 states, see [figs/AXITDC/TDCcore/control/controlFSM.png]:
- `INIT`: initialization, sets everything up and goes to `IDLE`
- `IDLE`: Waiting state, goes to `RUNNING` when `run` is set to 1, goes to `CLEAR` when `clr` is set.
- `RUNNING`: Data collection state, every time `valid` is 1 it writes the timestamp to the BRAM. Goes back to `IDLE` if `run` goes low. Goes to `RUN_DONE` when the BRAM is full.
- `RUN_DONE`: Wait until `run` is reset (goes to low), then goes to `IDLE`.
- `CLEAR`: Clear the BRAM then transitions to `CLR_DONE`
- `CLR_DONE`: Wait until `clr` is reset (goes to low), then goes to `IDLE`.

##### TDCchannel.vhd
**Top-level design file**
Connects all the components together.
- it takes in: the clock `clk`. the `hit` signal as well as 2 AXI control signals: `run` to collect data and `clr` to clear the BRAM. it outputs 2 of those AXI control signals `rdy` and `full`, all of these are directly sent to`control.vhd`. 
- it outputs data for the BRAM: `addr` the address, `data`, the ... well, the data and `we` the control signals (8-bits) enabling the write operation in the BRAM.
There is not much more to say, this file mainly pieces everything together: the `delayLine`, the `encoder`, the `counter` and of course `control`. The only "logic" implemented in this file is the timestamp concatenation.

#### AXI interfaces
##### AXITDC.vhd
This file is responsible for connecting the AXI interfaces with our `TDCchannel`. We need these interfaces because we want to create a hardware peripheral capable of communicating with the Zynq PS via AXI interconnect.
- The AXI GPIO core seems to be used for 4 pins only, 2 in, 2 out. They correspond to the TDC control signals `clr`, `run`, `rdy` and `full`.
	- Because of CDC, synchronizers (see `sync.vhd`) are used. These take "asynchronous" (different clock frequency) control signals (1-bit) and synchronize them on the target clock (`clk` for our system or `s_axi_aclk` for the GPIO)
- The TDC is wired to the BRAM and its control signals to the AXI GPIO core.
- The BRAM has 2 ports: one is wired to the BRAM Controller, the other one to the TDC
	- ==For some reasons== the address is shifted by 3-bits (goes from `ADDR_WIDTH+3` to `3`)
	- The port of the BRAM connected to the BRAM Controller allows memory-mapped access to the BRAm by the Zynq PS (==i.e., we can read our time tags from the cpu?==).

### Clocks
The AXI interconnect (==and the GPIO and so on==?) runs with a clock of 100MHz from the PS.
The MMCM (Clock-wizard) generates a 350MHz clock for the TDC cores.
### Timestamp
The full timestamps are 64-bits long, including 21 unused (set to 0).
- 11 (from 42 to 31) are used for the `trigger-count`, ==from what i understand==, it's the number of events since the last `CLEAR`.
- 32 bits are actually used for the timestamp (**Tunable in TDCChannel.vhd**):
	- 24 for the coarse counting
	- 8 for the fine
See [figs/AXITDC/timestamp.png].

***

# Original info from fork
## A fast high-resolution time-to-digital converter for the Red Pitaya Zynq-7010 SoC
Tested on Red Pitaya STEMLab 125-10 and STEMLab 125-14

Author: Michel Adamic ada.mic94@gmail.com

### Performance
TDC core frequency: 350 MHz\
No. of delay line taps: 192 (configurable)\
Time resolution per channel: >11 ps\
Accuracy: <10 ppm\
DNL: -1 to +4.5 LSB\
INL: +0.5 to +8.5 LSB\
Measurement range: 47.9 ms\
Dead time: ~14 ns\
Max speed: ~70 MS/s

### Included folders
*AXITDC*\
TDC channel IP. Includes VHDL source files, test benches and customized Xilinx IP cores.

*board*\
Red Pitaya board definition files.

*figs*\
Various figures and schematics of the TDC design.

*matlab*
- TDCgui4.mlapp - MATLAB App Designer graphical user interface application.

*setup*\
Files required to run the TDC system on the Red Pitaya board.
- TDCServer2.c - a Linux-based C program for the Zynq ARM core, which communicates with the TDC channels via the "mmap" system call. Addresses are set in the Address Editor of the TDCsystem project.
- PLclock script - contains bash commands for lowering the PL clock frequency from 125 to 100 MHz. Has to be executed before TDC implementation.
- TDCsystem_wrapper.bit - FPGA bitstream.

*src*\
Source files for creating a two-channel TDC system example project.

### 2-channel TDC system example project
1. Open Vivado 2018.2
2. Using the Tcl Console, navigate to the "zynq_tdc/" folder and execute "source make_project.tcl"
3. Complete the synthesis & implementation steps

If you don't want to run these steps and create your own FPGA bitstream, you can use the one already provided in the *setup* folder.

### Setup on the Red Pitaya system (STEMLab 125-10 or 125-14)
1. Copy the contents of the *setup* folder (FPGA bitstream, PLclock script and C server) on the Red Pitaya system
2. Run PLclock ("./PLclock") to lower the Zynq PL frequency to 100 MHz
3. Load the FPGA configuration ("cat TDCsystem_wrapper.bit > /dev/xdevcfg")
4. Compile and run the C server ("gcc -o TDCserver TDCserver2.c" and "./TDCserver")
5. On a client PC, start the MATLAB GUI application in Matlab App Designer to connect to the TDC system

TDC inputs are located on E1 extension connector pins 17 & 18 (connected to FPGA pins M14 & M15), voltage standard = LVCMOS33 (3,3 V). The TDCs are rising-edge sensitive, i.e. a timestamp is generated for each 0->1 transition.

## Links
IEEE paper: https://ieeexplore.ieee.org/abstract/document/8904850 \
My thesis (in Slovene): https://repozitorij.uni-lj.si/IzpisGradiva.php?id=117846&lang=eng \
Red Pitaya docs, schematics etc.: https://redpitaya.readthedocs.io/en/latest/
