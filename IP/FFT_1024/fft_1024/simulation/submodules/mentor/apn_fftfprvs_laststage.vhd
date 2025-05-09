-- (C) 2001-2018 Intel Corporation. All rights reserved.
-- Your use of Intel Corporation's design tools, logic functions and other 
-- software and tools, and its AMPP partner logic functions, and any output 
-- files from any of the foregoing (including device programming or simulation 
-- files), and any associated documentation or information are expressly subject 
-- to the terms and conditions of the Intel Program License Subscription 
-- Agreement, Intel FPGA IP License Agreement, or other applicable 
-- license agreement, including, without limitation, that your use is for the 
-- sole purpose of programming logic devices manufactured by Intel and sold by 
-- Intel or its authorized distributors.  Please refer to the applicable 
-- agreement for further details.



LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;
USE ieee.std_logic_arith.all; 

library work;
use work.auk_dspip_math_pkg.all;
USE work.auk_fft_pkg.all;

--***************************************************
--***                                             ***
--***   ALTERA SINGLE PRECISION FFT CORE          ***
--***                                             ***
--***   APN_FFTFPRVS_LASTSTAGE                    ***
--***                                             ***
--***   Function: Radix 4 FFT (stages of Radix    ***
--***   4^n DFT)                                  ***
--***                                             ***
--***   29/11/09 ML                               ***
--***                                             ***
--***   (c) 2009 Altera Corporation               ***
--***                                             ***
--***   Change History                            ***
--***                                             ***
--***                                             ***
--***                                             ***
--***                                             ***
--***                                             ***
--***************************************************

ENTITY apn_fftfprvs_laststage IS
GENERIC (
         device_family: string;
         input_format : string := "NATURAL_ORDER";
         addwidth     : positive := 4;
         delay        : positive := 4;
         accuracy     : natural := 1;
         dsp          : natural := 0
        );
PORT (
      sysclk    : IN  STD_LOGIC;
      reset     : IN  STD_LOGIC;
      enable    : IN  STD_LOGIC;
      startin   : IN  STD_LOGIC;
      radix     : IN  STD_LOGIC;
      stg_sel   : IN  STD_LOGIC;
      realin    : IN  STD_LOGIC_VECTOR (32 DOWNTO 1);
      imagin    : IN  STD_LOGIC_VECTOR (32 DOWNTO 1);
      realout   : OUT STD_LOGIC_VECTOR (32 DOWNTO 1);
      imagout   : OUT STD_LOGIC_VECTOR (32 DOWNTO 1);
      startout  : OUT STD_LOGIC
     );
END apn_fftfprvs_laststage;

ARCHITECTURE rtl OF apn_fftfprvs_laststage IS
  constant internal_data_width : integer := get_internal_data_width(dsp, device_family);
  type tapfftype IS ARRAY (6 DOWNTO 1) OF STD_LOGIC_VECTOR (32 DOWNTO 1);
  type muxfftype IS ARRAY (4 DOWNTO 1) OF STD_LOGIC_VECTOR (internal_data_width DOWNTO 1);
  type expmuxtype IS ARRAY (4 DOWNTO 1) OF STD_LOGIC_VECTOR (8 DOWNTO 1);
  type manmuxtype IS ARRAY (4 DOWNTO 1) OF STD_LOGIC_VECTOR (23 DOWNTO 1);
  type mannodetype IS ARRAY (4 DOWNTO 1) OF STD_LOGIC_VECTOR (32 DOWNTO 1);
  type tapffdctype IS ARRAY (4 DOWNTO 1) OF STD_LOGIC_VECTOR (32 DOWNTO 1);

  signal starthalfnode, startfullnode : STD_LOGIC;
  signal starthalfff  : STD_LOGIC_VECTOR (delay+delay/2   DOWNTO 1);
  signal startfullff  : STD_LOGIC_VECTOR (delay+delay/2-2 DOWNTO 1);
  signal startff      : STD_LOGIC_VECTOR (20 DOWNTO 1);
  signal countff : STD_LOGIC_VECTOR (addwidth DOWNTO 1);

  signal delzeronode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delonehalfnode, delonefullnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal deltwohalfnode, deltwofullnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delthrhalfnode, delthrfullnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delforhalfnode, delforfullnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delfivhalfnode, delfivfullnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delsixhalfnode, delsixfullnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delonenode, deltwonode, delthrnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal delfornode, delfivnode, delsixnode : STD_LOGIC_VECTOR (64 DOWNTO 1);
  signal realinff, imaginff : STD_LOGIC_VECTOR (32 DOWNTO 1);
  signal realff, imagff : tapfftype;
  signal realmuxff, imagmuxff : muxfftype;
  signal realff_dc1, realff_dc2, realff_dc3, realff_dc4 : tapffdctype;
  signal imagff_dc1, imagff_dc2, imagff_dc3, imagff_dc4 : tapffdctype;
  
  signal realsignmux, imagsignmux : STD_LOGIC_VECTOR (4 DOWNTO 1);
  signal realexpmux, imagexpmux : expmuxtype;
  signal realmanmux, imagmanmux : manmuxtype;
  
  signal selone, seltwo, selthr, selfor : STD_LOGIC;
  signal seloneff, seltwoff, selthrff, selforff : STD_LOGIC;
  signal realoutnode, imagoutnode : STD_LOGIC_VECTOR (32 DOWNTO 1);
  signal onebit : STD_LOGIC;

  signal startoutnode : STD_LOGIC;

  component apn_fftfp_del 
  GENERIC (
           delay : positive := 64;
           datawidth : positive := 18
          );
  PORT (
        sysclk : IN STD_LOGIC;
        enable : IN STD_LOGIC;
        datain : IN STD_LOGIC_VECTOR (datawidth DOWNTO 1);
        dataouthalf, dataoutfull : OUT STD_LOGIC_VECTOR (datawidth DOWNTO 1)
       );
  end component;

  component apn_fftfp_shift
  GENERIC (
           delay : positive := 64;
           datawidth : positive := 18
          );
  PORT (
        sysclk : IN STD_LOGIC;
        enable : IN STD_LOGIC;
        datain : IN STD_LOGIC_VECTOR (datawidth DOWNTO 1);
        dataouthalf, dataoutfull : OUT STD_LOGIC_VECTOR (datawidth DOWNTO 1)
       );
  end component;
  
  component apn_fftfp_dft4
  PORT (
        sysclk  : IN STD_LOGIC;
        reset   : IN STD_LOGIC;
        enable  : IN STD_LOGIC;
        startin : IN STD_LOGIC;
        realina : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        imagina : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        realinb : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        imaginb : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        realinc : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        imaginc : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        realind : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        imagind : IN STD_LOGIC_VECTOR (40 DOWNTO 1);
        startout : OUT STD_LOGIC;
        realout : OUT STD_LOGIC_VECTOR (32 DOWNTO 1);
        imagout : OUT STD_LOGIC_VECTOR (32 DOWNTO 1)
       );
   end component;
     component apn_fftfp_dft4_hdfp
  PORT (
        sysclk : IN STD_LOGIC;
        reset : IN STD_LOGIC;
        enable : IN STD_LOGIC;
        startin : IN STD_LOGIC;
        realina : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        imagina : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        realinb : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        imaginb : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        realinc : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        imaginc : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        realind : IN STD_LOGIC_VECTOR (32 DOWNTO 1);
        imagind : IN STD_LOGIC_VECTOR (32 DOWNTO 1);

        startout : OUT STD_LOGIC;
        realout : OUT STD_LOGIC_VECTOR (32 DOWNTO 1);
        imagout : OUT STD_LOGIC_VECTOR (32 DOWNTO 1)
       );
   end component;
BEGIN

  --*** to be added - after reset, keep output of delstart low until passed through,
  --*** in case '1's still in buffer from last fft
  
  -- startin 2 cycles early, so can start twidadd generation 2 clocks before
  starthalfnode <= starthalfff(delay+delay/2-2);
  startfullnode <= startfullff(delay+delay/2-2);  

  -- This implements the DelayNetwork ------------------------------------------
  ------------------------------------------------------------------------------  
  gdznr: FOR k IN 1 TO 32 GENERATE
    delzeronode(k) <= realin(k) AND stg_sel;
  END GENERATE;  
  gdzni: FOR k IN 33 TO 64 GENERATE
    delzeronode(k) <= imagin(k-32) AND stg_sel;
  END GENERATE;  
  
  gdela: IF (delay < 8) GENERATE
    delone: apn_fftfp_del
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delzeronode,
              dataouthalf=>delonehalfnode,dataoutfull=>delonefullnode);     
    deltwo: apn_fftfp_del
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delonenode,
              dataouthalf=>deltwohalfnode,dataoutfull=>deltwofullnode); 
    delthr: apn_fftfp_del
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>deltwonode,
              dataouthalf=>delthrhalfnode,dataoutfull=>delthrfullnode); 
    delfor: apn_fftfp_del
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delthrnode,
              dataouthalf=>delforhalfnode,dataoutfull=>delforfullnode);     
    delfiv: apn_fftfp_del
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delfornode,
              dataouthalf=>delfivhalfnode,dataoutfull=>delfivfullnode);                 
    delsix: apn_fftfp_del
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delfivnode,
              dataouthalf=>delsixhalfnode,dataoutfull=>delsixfullnode);
  END GENERATE;
  
  gsftb: IF (delay > 7) GENERATE
    delone: apn_fftfp_shift
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delzeronode,
              dataouthalf=>delonehalfnode,dataoutfull=>delonefullnode);     
    deltwo: apn_fftfp_shift
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delonenode,
              dataouthalf=>deltwohalfnode,dataoutfull=>deltwofullnode); 
    delthr: apn_fftfp_shift
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>deltwonode,
              dataouthalf=>delthrhalfnode,dataoutfull=>delthrfullnode); 
    delfor: apn_fftfp_shift
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delthrnode,
              dataouthalf=>delforhalfnode,dataoutfull=>delforfullnode);     
    delfiv: apn_fftfp_shift
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delfornode,
              dataouthalf=>delfivhalfnode,dataoutfull=>delfivfullnode);                 
    delsix: apn_fftfp_shift
    GENERIC MAP(delay=>delay,datawidth=>64)
    PORT MAP (sysclk=>sysclk,enable=>enable,
              datain=>delfivnode,
              dataouthalf=>delsixhalfnode,dataoutfull=>delsixfullnode);
  END GENERATE; 
  
  -- selecting half or full delay depending on whether Radix-2 or Radix-4 is calculated
  gda: FOR k IN 1 TO 64 GENERATE
    delonenode(k) <= (delonehalfnode(k) AND radix) OR (delonefullnode(k) AND NOT(radix));
    deltwonode(k) <= (deltwohalfnode(k) AND radix) OR (deltwofullnode(k) AND NOT(radix));
    delthrnode(k) <= (delthrhalfnode(k) AND radix) OR (delthrfullnode(k) AND NOT(radix));
    delfornode(k) <= (delforhalfnode(k) AND radix) OR (delforfullnode(k) AND NOT(radix));
    delfivnode(k) <= (delfivhalfnode(k) AND radix) OR (delfivfullnode(k) AND NOT(radix));
    delsixnode(k) <= (delsixhalfnode(k) AND radix) OR (delsixfullnode(k) AND NOT(radix));
  END GENERATE;             

  pda: PROCESS (reset, sysclk) 
  BEGIN
  
    IF (reset = '1') THEN
    
      FOR k IN 1 TO delay+delay/2 LOOP
        starthalfff(k) <= '0';
      END LOOP;
      FOR k IN 1 TO delay+delay/2-2 LOOP
        startfullff(k) <= '0';
      END LOOP;

      FOR k IN 1 TO 20 LOOP
        startff(k) <= '0';
      END LOOP;
      FOR k IN 1 TO addwidth LOOP
        countff(k) <= '0';
      END LOOP;
      seloneff <= '0';
      seltwoff <= '0';
      selthrff <= '0';
      selforff <= '0';


    ELSIF (rising_edge(sysclk)) THEN

      IF (enable = '1') THEN

        IF (stg_sel = '1') THEN
          starthalfff(1) <= startin;
        ELSE
          starthalfff(1) <= '0';
        END IF;
        
        startfullff(1) <= starthalfff(delay+delay/2) AND NOT(radix);
        FOR k IN 2 TO delay+delay/2 LOOP
          starthalfff(k) <= starthalfff(k-1);
        END LOOP;
        FOR k IN 2 TO delay+delay/2-2 LOOP
          startfullff(k) <= startfullff(k-1);
        END LOOP;
    
        startff(1) <= (starthalfnode AND radix) OR (startfullnode AND NOT(radix));
        FOR k IN 2 TO 20 LOOP
          startff(k) <= startff(k-1);
        END LOOP;

        IF (stg_sel = '1') THEN
          realinff <= realin;
          imaginff <= imagin;
        ELSE
          realinff <= (others => '0');
          imaginff <= (others => '0');
        END IF;
        -- Outputs from DelayNetwork
        realff(1)(32 DOWNTO 1) <= delonenode(32 DOWNTO 1);
        imagff(1)(32 DOWNTO 1) <= delonenode(64 DOWNTO 33);
        realff(2)(32 DOWNTO 1) <= deltwonode(32 DOWNTO 1);
        imagff(2)(32 DOWNTO 1) <= deltwonode(64 DOWNTO 33);
        realff(3)(32 DOWNTO 1) <= delthrnode(32 DOWNTO 1);
        imagff(3)(32 DOWNTO 1) <= delthrnode(64 DOWNTO 33);
        realff(4)(32 DOWNTO 1) <= delfornode(32 DOWNTO 1);
        imagff(4)(32 DOWNTO 1) <= delfornode(64 DOWNTO 33);
        realff(5)(32 DOWNTO 1) <= delfivnode(32 DOWNTO 1);
        imagff(5)(32 DOWNTO 1) <= delfivnode(64 DOWNTO 33);
        realff(6)(32 DOWNTO 1) <= delsixnode(32 DOWNTO 1);
        imagff(6)(32 DOWNTO 1) <= delsixnode(64 DOWNTO 33);
       
        IF (startff(2) = '1') THEN
          countff <= countff + 1;
        ELSIF (startff(2) = '0') THEN
          FOR k IN 1 TO addwidth LOOP
            countff(k) <= '0';
          END LOOP;
        END IF;

        seloneff <= selone;
        seltwoff <= seltwo;
        selthrff <= selthr;
        selforff <= selfor;
        

      END IF;
      
    END IF;
      
  END PROCESS;
  
  -- {1,1,1,1)
  natural_order1 : IF input_format /= "-N/2_to_N/2" GENERATE
    realsignmux(1) <= (realff(3)(32) AND seloneff) OR 
                      (realff(4)(32) AND seltwoff) OR
                      (realff(5)(32) AND selthrff) OR
                      (realff(6)(32) AND selforff);
    imagsignmux(1) <= (imagff(3)(32) AND seloneff) OR 
                      (imagff(4)(32) AND seltwoff) OR
                      (imagff(5)(32) AND selthrff) OR
                      (imagff(6)(32) AND selforff);
    gmxone: FOR k IN 1 TO 8 GENERATE
      realexpmux(1)(k) <= (realff(3)(k+23) AND seloneff) OR 
                          (realff(4)(k+23) AND seltwoff) OR
                          (realff(5)(k+23) AND selthrff) OR
                          (realff(6)(k+23) AND selforff);
      imagexpmux(1)(k) <= (imagff(3)(k+23) AND seloneff) OR 
                          (imagff(4)(k+23) AND seltwoff) OR
                          (imagff(5)(k+23) AND selthrff) OR
                          (imagff(6)(k+23) AND selforff);
    END GENERATE;
    gmmone: FOR k IN 1 TO 23 GENERATE
      realmanmux(1)(k) <= (realff(3)(k) AND seloneff) OR 
                          (realff(4)(k) AND seltwoff) OR
                          (realff(5)(k) AND selthrff) OR
                          (realff(6)(k) AND selforff);
      imagmanmux(1)(k) <= (imagff(3)(k) AND seloneff) OR 
                          (imagff(4)(k) AND seltwoff) OR
                          (imagff(5)(k) AND selthrff) OR
                          (imagff(6)(k) AND selforff);
    END GENERATE;
  END GENERATE natural_order1;
 
  dc_centered1 : IF input_format = "-N/2_to_N/2" GENERATE
    dc_mux1: process (stg_sel, realff, imagff)
    BEGIN
      IF stg_sel = '1' THEN
        realff_dc1(1) <= realff(1);
        realff_dc2(1) <= realff(2);
        realff_dc3(1) <= realff(3);
        realff_dc4(1) <= realff(4);
        imagff_dc1(1) <= imagff(1);
        imagff_dc2(1) <= imagff(2);
        imagff_dc3(1) <= imagff(3);
        imagff_dc4(1) <= imagff(4);
      ELSE
        realff_dc1(1) <= realff(3);
        realff_dc2(1) <= realff(4);
        realff_dc3(1) <= realff(5);
        realff_dc4(1) <= realff(6);
        imagff_dc1(1) <= imagff(3);
        imagff_dc2(1) <= imagff(4);
        imagff_dc3(1) <= imagff(5);
        imagff_dc4(1) <= imagff(6);
      END IF;
    END PROCESS dc_mux1;
    realsignmux(1) <= (realff_dc1(1)(32) AND seloneff) OR 
                      (realff_dc2(1)(32) AND seltwoff) OR
                      (realff_dc3(1)(32) AND selthrff) OR
                      (realff_dc4(1)(32) AND selforff);
    imagsignmux(1) <= (imagff_dc1(1)(32) AND seloneff) OR 
                      (imagff_dc2(1)(32) AND seltwoff) OR
                      (imagff_dc3(1)(32) AND selthrff) OR
                      (imagff_dc4(1)(32) AND selforff);
    gmxone: FOR k IN 1 TO 8 GENERATE
      realexpmux(1)(k) <= (realff_dc1(1)(k+23) AND seloneff) OR 
                          (realff_dc2(1)(k+23) AND seltwoff) OR
                          (realff_dc3(1)(k+23) AND selthrff) OR
                          (realff_dc4(1)(k+23) AND selforff);
      imagexpmux(1)(k) <= (imagff_dc1(1)(k+23) AND seloneff) OR 
                          (imagff_dc2(1)(k+23) AND seltwoff) OR
                          (imagff_dc3(1)(k+23) AND selthrff) OR
                          (imagff_dc4(1)(k+23) AND selforff);
    END GENERATE;
    gmmone: FOR k IN 1 TO 23 GENERATE
      realmanmux(1)(k) <= (realff_dc1(1)(k) AND seloneff) OR 
                          (realff_dc2(1)(k) AND seltwoff) OR
                          (realff_dc3(1)(k) AND selthrff) OR
                          (realff_dc4(1)(k) AND selforff);
      imagmanmux(1)(k) <= (imagff_dc1(1)(k) AND seloneff) OR 
                          (imagff_dc2(1)(k) AND seltwoff) OR
                          (imagff_dc3(1)(k) AND selthrff) OR
                          (imagff_dc4(1)(k) AND selforff);
    END GENERATE;
  END GENERATE dc_centered1;

  
  
  -- {1,-j,-1,j}
  natural_order2 : IF input_format /= "-N/2_to_N/2" GENERATE
    realsignmux(2) <= (realff(2)(32)      AND seloneff) OR
                      (imagff(3)(32)      AND seltwoff) OR
                      (NOT(realff(4)(32)) AND selthrff) OR
                      (NOT(imagff(5)(32)) AND selforff);
    imagsignmux(2) <= (imagff(2)(32)      AND seloneff) OR
                      (NOT(realff(3)(32)) AND seltwoff) OR
                      (NOT(imagff(4)(32)) AND selthrff) OR
                      (realff(5)(32)      AND selforff);
    gmxtwo: FOR k IN 1 TO 8 GENERATE
      realexpmux(2)(k) <= (realff(2)(k+23) AND seloneff) OR
                          (imagff(3)(k+23) AND seltwoff) OR
                          (realff(4)(k+23) AND selthrff) OR
                          (imagff(5)(k+23) AND selforff);
      imagexpmux(2)(k) <= (imagff(2)(k+23) AND seloneff) OR
                          (realff(3)(k+23) AND seltwoff) OR
                          (imagff(4)(k+23) AND selthrff) OR
                          (realff(5)(k+23) AND selforff);
    END GENERATE;
    gmmtwo: FOR k IN 1 TO 23 GENERATE
      realmanmux(2)(k) <= (realff(2)(k) AND seloneff) OR
                          (imagff(3)(k) AND seltwoff) OR
                          (realff(4)(k) AND selthrff) OR
                          (imagff(5)(k) AND selforff);
      imagmanmux(2)(k) <= (imagff(2)(k) AND seloneff) OR
                          (realff(3)(k) AND seltwoff) OR
                          (imagff(4)(k) AND selthrff) OR
                          (realff(5)(k) AND selforff);
    END GENERATE;
  END GENERATE natural_order2;

  dc_centered2 : IF input_format = "-N/2_to_N/2" GENERATE
    dc_mux2: process (stg_sel, realinff, realff, imaginff, imagff)
    BEGIN
      IF stg_sel = '1' THEN
        realff_dc1(2) <= realinff;
        imagff_dc2(2) <= imagff(1);
        realff_dc3(2) <= realff(2);
        imagff_dc4(2) <= imagff(3);
        imagff_dc1(2) <= imaginff;
        realff_dc2(2) <= realff(1);
        imagff_dc3(2) <= imagff(2);
        realff_dc4(2) <= realff(3);
      ELSE
        realff_dc1(2) <= realff(2);
        imagff_dc2(2) <= imagff(3);
        realff_dc3(2) <= realff(4);
        imagff_dc4(2) <= imagff(5);
        imagff_dc1(2) <= imagff(2);
        realff_dc2(2) <= realff(3);
        imagff_dc3(2) <= imagff(4);
        realff_dc4(2) <= realff(5);
      END IF;
    END PROCESS dc_mux2;
    realsignmux(2) <= (realff_dc1(2)(32)      AND seloneff) OR
                      (imagff_dc2(2)(32)      AND seltwoff) OR
                      (NOT(realff_dc3(2)(32)) AND selthrff) OR
                      (NOT(imagff_dc4(2)(32)) AND selforff);
    imagsignmux(2) <= (imagff_dc1(2)(32)      AND seloneff) OR
                      (NOT(realff_dc2(2)(32)) AND seltwoff) OR
                      (NOT(imagff_dc3(2)(32)) AND selthrff) OR
                      (realff_dc4(2)(32)      AND selforff);
    gmxtwo: FOR k IN 1 TO 8 GENERATE
      realexpmux(2)(k) <= (realff_dc1(2)(k+23) AND seloneff) OR
                          (imagff_dc2(2)(k+23) AND seltwoff) OR
                          (realff_dc3(2)(k+23) AND selthrff) OR
                          (imagff_dc4(2)(k+23) AND selforff);
      imagexpmux(2)(k) <= (imagff_dc1(2)(k+23) AND seloneff) OR
                          (realff_dc2(2)(k+23) AND seltwoff) OR
                          (imagff_dc3(2)(k+23) AND selthrff) OR
                          (realff_dc4(2)(k+23) AND selforff);
    END GENERATE;
    gmmtwo: FOR k IN 1 TO 23 GENERATE
      realmanmux(2)(k) <= (realff_dc1(2)(k) AND seloneff) OR
                          (imagff_dc2(2)(k) AND seltwoff) OR
                          (realff_dc3(2)(k) AND selthrff) OR
                          (imagff_dc4(2)(k) AND selforff);
      imagmanmux(2)(k) <= (imagff_dc1(2)(k) AND seloneff) OR
                          (realff_dc2(2)(k) AND seltwoff) OR
                          (imagff_dc3(2)(k) AND selthrff) OR
                          (realff_dc4(2)(k) AND selforff);
    END GENERATE;
  END GENERATE dc_centered2;
  
  
    
  --{1,-1,1,-1}
  natural_order3 : IF input_format /= "-N/2_to_N/2" GENERATE
    realsignmux(3) <= (realff(1)(32)      AND seloneff) OR
                      (NOT(realff(2)(32)) AND seltwoff) OR
                      (realff(3)(32)      AND selthrff) OR
                      (NOT(realff(4)(32)) AND selforff);
    imagsignmux(3) <= (imagff(1)(32)      AND seloneff) OR
                      (NOT(imagff(2)(32)) AND seltwoff) OR
                      (imagff(3)(32)      AND selthrff) OR
                      (NOT(imagff(4)(32)) AND selforff);
    gmxthr: FOR k IN 1 TO 8 GENERATE
      realexpmux(3)(k) <= (realff(1)(k+23) AND seloneff) OR
                          (realff(2)(k+23) AND seltwoff) OR
                          (realff(3)(k+23) AND selthrff) OR
                          (realff(4)(k+23) AND selforff);
      imagexpmux(3)(k) <= (imagff(1)(k+23) AND seloneff) OR
                          (imagff(2)(k+23) AND seltwoff) OR
                          (imagff(3)(k+23) AND selthrff) OR
                          (imagff(4)(k+23) AND selforff);
    END GENERATE;
    gmmthr: FOR k IN 1 TO 23 GENERATE
      realmanmux(3)(k) <= (realff(1)(k) AND seloneff) OR
                          (realff(2)(k) AND seltwoff) OR
                          (realff(3)(k) AND selthrff) OR
                          (realff(4)(k) AND selforff);
      imagmanmux(3)(k) <= (imagff(1)(k) AND seloneff) OR
                          (imagff(2)(k) AND seltwoff) OR
                          (imagff(3)(k) AND selthrff) OR
                          (imagff(4)(k) AND selforff);
    END GENERATE;
  END GENERATE natural_order3;
 
  dc_centered3 : IF input_format = "-N/2_to_N/2" GENERATE
    dc_mux3: process (stg_sel, realff, imagff)
    BEGIN
      IF stg_sel = '1' THEN
        realff_dc1(3) <= realff(3);
        realff_dc2(3) <= realff(4);
        realff_dc3(3) <= realff(5);
        realff_dc4(3) <= realff(6);
        imagff_dc1(3) <= imagff(3);
        imagff_dc2(3) <= imagff(4);
        imagff_dc3(3) <= imagff(5);
        imagff_dc4(3) <= imagff(6);
      ELSE
        realff_dc1(3) <= realff(1);
        realff_dc2(3) <= realff(2);
        realff_dc3(3) <= realff(3);
        realff_dc4(3) <= realff(4);
        imagff_dc1(3) <= imagff(1);
        imagff_dc2(3) <= imagff(2);
        imagff_dc3(3) <= imagff(3);
        imagff_dc4(3) <= imagff(4);
      END IF;
    END PROCESS dc_mux3;
    realsignmux(3) <= (realff_dc1(3)(32)      AND seloneff) OR
                      (NOT(realff_dc2(3)(32)) AND seltwoff) OR
                      (realff_dc3(3)(32)      AND selthrff) OR
                      (NOT(realff_dc4(3)(32)) AND selforff);
    imagsignmux(3) <= (imagff_dc1(3)(32)      AND seloneff) OR
                      (NOT(imagff_dc2(3)(32)) AND seltwoff) OR
                      (imagff_dc3(3)(32)      AND selthrff) OR
                      (NOT(imagff_dc4(3)(32)) AND selforff);
    gmxthr: FOR k IN 1 TO 8 GENERATE
      realexpmux(3)(k) <= (realff_dc1(3)(k+23) AND seloneff) OR
                          (realff_dc2(3)(k+23) AND seltwoff) OR
                          (realff_dc3(3)(k+23) AND selthrff) OR
                          (realff_dc4(3)(k+23) AND selforff);
      imagexpmux(3)(k) <= (imagff_dc1(3)(k+23) AND seloneff) OR
                          (imagff_dc2(3)(k+23) AND seltwoff) OR
                          (imagff_dc3(3)(k+23) AND selthrff) OR
                          (imagff_dc4(3)(k+23) AND selforff);
    END GENERATE;
    gmmthr: FOR k IN 1 TO 23 GENERATE
      realmanmux(3)(k) <= (realff_dc1(3)(k) AND seloneff) OR
                          (realff_dc2(3)(k) AND seltwoff) OR
                          (realff_dc3(3)(k) AND selthrff) OR
                          (realff_dc4(3)(k) AND selforff);
      imagmanmux(3)(k) <= (imagff_dc1(3)(k) AND seloneff) OR
                          (imagff_dc2(3)(k) AND seltwoff) OR
                          (imagff_dc3(3)(k) AND selthrff) OR
                          (imagff_dc4(3)(k) AND selforff);
    END GENERATE;
  END GENERATE dc_centered3;

  
                       
  -- {1,j,-1,-j}       
  natural_order4 : IF input_format /= "-N/2_to_N/2" GENERATE
    realsignmux(4) <= (realinff(32)       AND seloneff) OR
                      (NOT(imagff(1)(32)) AND seltwoff) OR
                      (NOT(realff(2)(32)) AND selthrff) OR
                      (imagff(3)(32)      AND selforff);
    imagsignmux(4) <= (imaginff(32)       AND seloneff) OR
                      (realff(1)(32)      AND seltwoff) OR
                      (NOT(imagff(2)(32)) AND selthrff) OR
                      (NOT(realff(3)(32)) AND selforff);                      
    gmxfor: FOR k IN 1 TO 8 GENERATE                       
      realexpmux(4)(k) <= (realinff(k+23)  AND seloneff) OR
                          (imagff(1)(k+23) AND seltwoff) OR
                          (realff(2)(k+23) AND selthrff) OR
                          (imagff(3)(k+23) AND selforff);
      imagexpmux(4)(k) <= (imaginff(k+23)  AND seloneff) OR
                          (realff(1)(k+23) AND seltwoff) OR
                          (imagff(2)(k+23) AND selthrff) OR
                          (realff(3)(k+23) AND selforff);
    END GENERATE;
    gmmfor: FOR k IN 1 TO 23 GENERATE
      realmanmux(4)(k) <= (realinff(k)  AND seloneff) OR
                          (imagff(1)(k) AND seltwoff) OR
                          (realff(2)(k) AND selthrff) OR
                          (imagff(3)(k) AND selforff);
      imagmanmux(4)(k) <= (imaginff(k)  AND seloneff) OR
                          (realff(1)(k) AND seltwoff) OR
                          (imagff(2)(k) AND selthrff) OR
                          (realff(3)(k) AND selforff);
    END GENERATE;
  END GENERATE natural_order4;

   dc_centered4 : IF input_format = "-N/2_to_N/2" GENERATE
    dc_mux4: process (stg_sel, realinff, realff, imaginff, imagff)
    BEGIN
      IF stg_sel = '1' THEN
        realff_dc1(4) <= realff(2);
        imagff_dc2(4) <= imagff(3);
        realff_dc3(4) <= realff(4);
        imagff_dc4(4) <= imagff(5);
        imagff_dc1(4) <= imagff(2);
        realff_dc2(4) <= realff(3);
        imagff_dc3(4) <= imagff(4);
        realff_dc4(4) <= realff(5);
      ELSE
        realff_dc1(4) <= realinff;
        imagff_dc2(4) <= imagff(1);
        realff_dc3(4) <= realff(2);
        imagff_dc4(4) <= imagff(3);
        imagff_dc1(4) <= imaginff;
        realff_dc2(4) <= realff(1);
        imagff_dc3(4) <= imagff(2);
        realff_dc4(4) <= realff(3);
      END IF;
    END PROCESS dc_mux4;
    realsignmux(4) <= (realff_dc1(4)(32)      AND seloneff) OR
                      (NOT(imagff_dc2(4)(32)) AND seltwoff) OR
                      (NOT(realff_dc3(4)(32)) AND selthrff) OR
                      (imagff_dc4(4)(32)      AND selforff);
    imagsignmux(4) <= (imagff_dc1(4)(32)      AND seloneff) OR
                      (realff_dc2(4)(32)      AND seltwoff) OR
                      (NOT(imagff_dc3(4)(32)) AND selthrff) OR
                      (NOT(realff_dc4(4)(32)) AND selforff);                      
    gmxfor: FOR k IN 1 TO 8 GENERATE                       
      realexpmux(4)(k) <= (realff_dc1(4)(k+23) AND seloneff) OR
                          (imagff_dc2(4)(k+23) AND seltwoff) OR
                          (realff_dc3(4)(k+23) AND selthrff) OR
                          (imagff_dc4(4)(k+23) AND selforff);
      imagexpmux(4)(k) <= (imagff_dc1(4)(k+23) AND seloneff) OR
                          (realff_dc2(4)(k+23) AND seltwoff) OR
                          (imagff_dc3(4)(k+23) AND selthrff) OR
                          (realff_dc4(4)(k+23) AND selforff);
    END GENERATE;
    gmmfor: FOR k IN 1 TO 23 GENERATE
      realmanmux(4)(k) <= (realff_dc1(4)(k) AND seloneff) OR
                          (imagff_dc2(4)(k) AND seltwoff) OR
                          (realff_dc3(4)(k) AND selthrff) OR
                          (imagff_dc4(4)(k) AND selforff);
      imagmanmux(4)(k) <= (imagff_dc1(4)(k) AND seloneff) OR
                          (realff_dc2(4)(k) AND seltwoff) OR
                          (imagff_dc3(4)(k) AND selthrff) OR
                          (realff_dc4(4)(k) AND selforff);
    END GENERATE;
  END GENERATE dc_centered4;
 
  
  
  selone <= (NOT(countff(addwidth))   AND NOT(countff(addwidth-1)) AND NOT(radix)) OR
            (NOT(countff(addwidth-1)) AND NOT(countff(addwidth-2)) AND     radix);        
  seltwo <= (NOT(countff(addwidth))   AND     countff(addwidth-1)  AND NOT(radix)) OR
            (NOT(countff(addwidth-1)) AND     countff(addwidth-2)  AND     radix);
  selthr <= (    countff(addwidth)    AND NOT(countff(addwidth-1)) AND NOT(radix)) OR
            (    countff(addwidth-1)  AND NOT(countff(addwidth-2)) AND     radix);  
  selfor <= (    countff(addwidth)    AND     countff(addwidth-1)  AND NOT(radix)) OR
            (    countff(addwidth-1)  AND     countff(addwidth-2)  AND     radix);


  process (sysclk, reset)
  begin
    if reset = '1' then
      startout  <= '0';
      realout   <= (others => '0');
      imagout   <= (others => '0');
    elsif rising_edge(sysclk) then
      if enable = '1' then
        if stg_sel = '1' then
          startout  <= startoutnode;
          realout   <= realoutnode;
          imagout   <= imagoutnode;
        else
          startout  <= startin;
          realout   <= realin;
          imagout   <= imagin;
        end if;
      end if;
    end if;
  end process;






  custom_width_adaptor:  IF not(dsp = 3) GENERATE
  signal realsignmuxff, imagsignmuxff : STD_LOGIC_VECTOR (4 DOWNTO 1);
  signal realexpmuxff, imagexpmuxff : expmuxtype;
  signal realmanmuxff, imagmanmuxff : manmuxtype;
  signal realmanprenode, imagmanprenode : mannodetype;
  signal realmangennode, imagmangennode : mannodetype;
  signal realmannode, imagmannode : mannodetype;
  signal realmux, imagmux : mannodetype;

  BEGIN


  
  core: apn_fftfp_dft4
  PORT MAP (sysclk=>sysclk,
            reset=>reset,
            enable=>enable,
            startin=>startff(5),
            realina=>realmuxff(1)(40 DOWNTO 1),imagina=>imagmuxff(1)(40 DOWNTO 1),
            realinb=>realmuxff(2)(40 DOWNTO 1),imaginb=>imagmuxff(2)(40 DOWNTO 1),
            realinc=>realmuxff(3)(40 DOWNTO 1),imaginc=>imagmuxff(3)(40 DOWNTO 1),
            realind=>realmuxff(4)(40 DOWNTO 1),imagind=>imagmuxff(4)(40 DOWNTO 1),
            startout=>startoutnode,
            realout=>realoutnode,imagout=>imagoutnode);



    conv: FOR i IN 1 TO 4 GENERATE
      realmangennode(i)(32 DOWNTO 28) <= "00000";
      realmangennode(i)(27) <= or_reduce(realexpmuxff(i));
      realmangennode(i)(26 DOWNTO 4) <= realmanmuxff(i)(23 DOWNTO 1);
      realmangennode(i)(3 DOWNTO 1) <= "000";
      grma: FOR k IN 1 TO 32 GENERATE
        realmanprenode(i)(k) <= realmangennode(i)(k) XOR realsignmuxff(i);
      END GENERATE;
      realmannode(i)(32 DOWNTO 1) <= realmanprenode(i)(32 DOWNTO 1) + realsignmuxff(i);
      
      imagmangennode(i)(32 DOWNTO 28) <= "00000";
      imagmangennode(i)(27) <= or_reduce(imagexpmuxff(i));
      imagmangennode(i)(26 DOWNTO 4) <= imagmanmuxff(i)(23 DOWNTO 1);
      imagmangennode(i)(3 DOWNTO 1) <= "000";
      gima: FOR k IN 1 TO 32 GENERATE
        imagmanprenode(i)(k) <= imagmangennode(i)(k) XOR imagsignmuxff(i);
      END GENERATE;
      imagmannode(i)(32 DOWNTO 1) <= imagmanprenode(i)(32 DOWNTO 1) + imagsignmuxff(i);               
    END GENERATE;



    conv_proc: PROCESS (sysclk, reset) 
    BEGIN
    
      IF (reset = '1') THEN

        realsignmuxff <= (others=>'0');
        imagsignmuxff <= (others=>'0');
        realexpmuxff <= (others=>(others=>'0'));
        imagexpmuxff <= (others=>(others=>'0'));

        realmanmuxff <= (others=>(others=>'0'));
        imagmanmuxff <= (others=>(others=>'0'));

        realmuxff <= (others=>(others=>'0'));
        imagmuxff <= (others=>(others=>'0'));


    
      ELSIF (rising_edge(sysclk)) THEN

        IF (enable = '1') THEN
          FOR k IN 1 TO 4 LOOP
            realmux(k) <= realsignmux(k) & realexpmux(k) & realmanmux(k);
            imagmux(k) <= imagsignmux(k) & imagexpmux(k) & imagmanmux(k);
          END LOOP;
          realsignmuxff(4 DOWNTO 1) <= realsignmux(4 DOWNTO 1);
          imagsignmuxff(4 DOWNTO 1) <= imagsignmux(4 DOWNTO 1);
          FOR k IN 1 TO 4 LOOP
            realexpmuxff(k)(8 DOWNTO 1) <= realexpmux(k)(8 DOWNTO 1);
            imagexpmuxff(k)(8 DOWNTO 1) <= imagexpmux(k)(8 DOWNTO 1);
          END LOOP;
          FOR k IN 1 TO 4 LOOP
            realmanmuxff(k)(23 DOWNTO 1) <= realmanmux(k)(23 DOWNTO 1);
            imagmanmuxff(k)(23 DOWNTO 1) <= imagmanmux(k)(23 DOWNTO 1);
          END LOOP;
        
          FOR k IN 1 TO 4 LOOP
            realmuxff(k) <= realmannode(k) & realexpmuxff(k);
            imagmuxff(k) <= imagmannode(k) & imagexpmuxff(k);
          END LOOP;

        END IF;
        
      END IF;
        
    END PROCESS;
    

  END GENERATE;

  single_width:  IF dsp = 3 GENERATE
  signal realmux, imagmux : mannodetype;
  begin


  
  core: apn_fftfp_dft4_hdfp
  PORT MAP (sysclk=>sysclk,
            reset=>reset,
            enable=>enable,
            startin=>startff(5),
            realina=>realmuxff(1),imagina=>imagmuxff(1),
            realinb=>realmuxff(2),imaginb=>imagmuxff(2),
            realinc=>realmuxff(3),imaginc=>imagmuxff(3),
            realind=>realmuxff(4),imagind=>imagmuxff(4),
            startout=>startoutnode,
            realout=>realoutnode,imagout=>imagoutnode);


    conv_proc: PROCESS (sysclk, reset) 
    BEGIN
    
      IF (reset = '1') THEN
      
            realmux <= (others=>(others=>'0'));
            imagmux <= (others=>(others=>'0'));
       
            realmuxff <= (others=>(others=>'0'));
            imagmuxff <= (others=>(others=>'0'));
    
      ELSIF (rising_edge(sysclk)) THEN

        IF (enable = '1') THEN

          FOR k IN 1 TO 4 LOOP
            realmux(k) <= realsignmux(k) & realexpmux(k) & realmanmux(k);
            imagmux(k) <= imagsignmux(k) & imagexpmux(k) & imagmanmux(k);
          END LOOP;

        
          FOR k IN 1 TO 4 LOOP
            realmuxff(k) <= realmux(k);
            imagmuxff(k) <= imagmux(k);
          END LOOP;

        END IF;
        
      END IF;
        
    END PROCESS;
    



  END GENERATE;


END rtl;

