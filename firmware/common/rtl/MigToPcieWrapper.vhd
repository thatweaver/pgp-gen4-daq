-------------------------------------------------------------------------------
-- File       : MigToPcieWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-03-06
-- Last update: 2018-02-23
-------------------------------------------------------------------------------
-- Description: Receives transfer requests representing data buffers pending
-- in local DRAM and moves data to CPU host memory over PCIe AXI interface.
-- Captures histograms of local DRAM buffer depth and PCIe target address FIFO
-- depth.  Needs an AxiStream to AXI channel to write histograms to host memory.
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-core', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.AxiDescPkg.all;
use work.MigPkg.all;

entity MigToPcieWrapper is
   generic (  LANES_G          : integer          := 4;
              NAPP_G           : integer          := 1;
              AXIL_BASE_ADDR_G : slv(31 downto 0) := x"00000000";
              AXI_ERROR_RESP_G : slv(1 downto 0)  := AXI_RESP_DECERR_C );
   port    ( -- Clock and reset
             axiClk           : in  sl; -- 200MHz
             axiRst           : in  sl; -- need a user reset to clear the pipeline
             usrRst           : out sl;
             -- AXI4 Interfaces to MIG
             axiReadMasters   : out AxiReadMasterArray (LANES_G-1 downto 0);
             axiReadSlaves    : in  AxiReadSlaveArray  (LANES_G-1 downto 0);
             -- AxiStream Interfaces from MIG (Data Mover command)
             dscReadMasters   : in  AxiDescMasterArray (LANES_G-1 downto 0);
             dscReadSlaves    : out AxiDescSlaveArray  (LANES_G-1 downto 0);
             -- AXI4 Interface to PCIe
             axiWriteMasters  : out AxiWriteMasterArray(LANES_G downto 0);
             axiWriteSlaves   : in  AxiWriteSlaveArray (LANES_G downto 0);
             -- AXI Lite Interface
             axilClk          : in  sl;
             axilRst          : in  sl;
             axilWriteMaster  : in  AxiLiteWriteMasterType;
             axilWriteSlave   : out AxiLiteWriteSlaveType;
             axilReadMaster   : in  AxiLiteReadMasterType;
             axilReadSlave    : out AxiLiteReadSlaveType;
             -- (axiClk domain)
             migConfig        : out MigConfigArray(LANES_G-1 downto 0);
             migStatus        : in  MigStatusArray(LANES_G-1 downto 0) );
end MigToPcieWrapper;

architecture mapping of MigToPcieWrapper is

  COMPONENT MigToPcie
    PORT (
      m_axi_mm2s_aclk : IN STD_LOGIC;
      m_axi_mm2s_aresetn : IN STD_LOGIC;
      mm2s_err : OUT STD_LOGIC;
      m_axis_mm2s_cmdsts_aclk : IN STD_LOGIC;
      m_axis_mm2s_cmdsts_aresetn : IN STD_LOGIC;
      s_axis_mm2s_cmd_tvalid : IN STD_LOGIC;
      s_axis_mm2s_cmd_tready : OUT STD_LOGIC;
      s_axis_mm2s_cmd_tdata : IN STD_LOGIC_VECTOR(79 DOWNTO 0);
      m_axis_mm2s_sts_tvalid : OUT STD_LOGIC;
      m_axis_mm2s_sts_tready : IN STD_LOGIC;
      m_axis_mm2s_sts_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      m_axis_mm2s_sts_tkeep : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
      m_axis_mm2s_sts_tlast : OUT STD_LOGIC;
      m_axi_mm2s_arid : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      m_axi_mm2s_araddr : OUT STD_LOGIC_VECTOR(37 DOWNTO 0);
      m_axi_mm2s_arlen : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      m_axi_mm2s_arsize : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      m_axi_mm2s_arburst : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      m_axi_mm2s_arprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      m_axi_mm2s_arcache : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      m_axi_mm2s_aruser : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      m_axi_mm2s_arvalid : OUT STD_LOGIC;
      m_axi_mm2s_arready : IN STD_LOGIC;
      m_axi_mm2s_rdata : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
      m_axi_mm2s_rresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
      m_axi_mm2s_rlast : IN STD_LOGIC;
      m_axi_mm2s_rvalid : IN STD_LOGIC;
      m_axi_mm2s_rready : OUT STD_LOGIC;
      m_axis_mm2s_tdata : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
      m_axis_mm2s_tkeep : OUT STD_LOGIC_VECTOR( 15 DOWNTO 0);
      m_axis_mm2s_tlast : OUT STD_LOGIC;
      m_axis_mm2s_tvalid : OUT STD_LOGIC;
      m_axis_mm2s_tready : IN STD_LOGIC;
      m_axi_s2mm_aclk : IN STD_LOGIC;
      m_axi_s2mm_aresetn : IN STD_LOGIC;
      s2mm_err : OUT STD_LOGIC;
      m_axis_s2mm_cmdsts_awclk : IN STD_LOGIC;
      m_axis_s2mm_cmdsts_aresetn : IN STD_LOGIC;
      s_axis_s2mm_cmd_tvalid : IN STD_LOGIC;
      s_axis_s2mm_cmd_tready : OUT STD_LOGIC;
      s_axis_s2mm_cmd_tdata : IN STD_LOGIC_VECTOR(79 DOWNTO 0);
      m_axis_s2mm_sts_tvalid : OUT STD_LOGIC;
      m_axis_s2mm_sts_tready : IN STD_LOGIC;
      m_axis_s2mm_sts_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      m_axis_s2mm_sts_tkeep : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
      m_axis_s2mm_sts_tlast : OUT STD_LOGIC;
      m_axi_s2mm_awid : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      m_axi_s2mm_awaddr : OUT STD_LOGIC_VECTOR(37 DOWNTO 0);
      m_axi_s2mm_awlen : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      m_axi_s2mm_awsize : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      m_axi_s2mm_awburst : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
      m_axi_s2mm_awprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
      m_axi_s2mm_awcache : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      m_axi_s2mm_awuser : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
      m_axi_s2mm_awvalid : OUT STD_LOGIC;
      m_axi_s2mm_awready : IN STD_LOGIC;
      m_axi_s2mm_wdata : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
      m_axi_s2mm_wstrb : OUT STD_LOGIC_VECTOR( 15 DOWNTO 0);
      m_axi_s2mm_wlast : OUT STD_LOGIC;
      m_axi_s2mm_wvalid : OUT STD_LOGIC;
      m_axi_s2mm_wready : IN STD_LOGIC;
      m_axi_s2mm_bresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
      m_axi_s2mm_bvalid : IN STD_LOGIC;
      m_axi_s2mm_bready : OUT STD_LOGIC;
      s_axis_s2mm_tdata : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
      s_axis_s2mm_tkeep : IN STD_LOGIC_VECTOR( 15 DOWNTO 0);
      s_axis_s2mm_tlast : IN STD_LOGIC;
      s_axis_s2mm_tvalid : IN STD_LOGIC;
      s_axis_s2mm_tready : OUT STD_LOGIC
      );
  END COMPONENT;

  signal axiRstN : sl;
  
  --  Assumes 40b memory addresses
  signal intDscReadMasters  : AxiDescMasterArray(LANES_G-1 downto 0);
  signal intDscReadSlaves   : AxiDescSlaveArray (LANES_G-1 downto 0) := (others=>AXI_DESC_SLAVE_INIT_C);
  signal intDscWriteMasters : AxiDescMasterArray(LANES_G-1 downto 0);
  signal intDscWriteSlaves  : AxiDescSlaveArray (LANES_G-1 downto 0) := (others=>AXI_DESC_SLAVE_INIT_C);

  signal intMasters       : AxiStreamMasterArray(LANES_G-1 downto 0);
  signal intSlaves        : AxiStreamSlaveArray (LANES_G-1 downto 0);

  signal dinTransfer    : Slv23Array(LANES_G-1 downto 0);
  signal doutTransfer   : Slv23Array(LANES_G-1 downto 0);
  signal dcountTransfer : Slv4Array (LANES_G-1 downto 0);
  signal rdTransfer     : slv       (LANES_G-1 downto 0);
  signal validTransfer  : slv       (LANES_G-1 downto 0);
  signal fullTransfer   : slv       (LANES_G-1 downto 0);
  signal wrTransfer     : slv       (LANES_G-1 downto 0);

  --  Assumes 16b buffer ids
  constant NAPP_C : integer := NAPP_G;
  signal dcountRamAddr  : Slv12Array(NAPP_C downto 0) := (others=>(others=>'0'));
  signal rdRamAddr      : slv       (NAPP_C downto 0) := (others=>'0');
  signal validRamAddr   : slv       (NAPP_C downto 0) := (others=>'0');
  signal doutRamAddr    : Slv64Array(NAPP_C downto 0) := (others=>(others=>'0'));
  signal doutWriteDesc  : Slv44Array(LANES_G-1 downto 0);
  signal dcountWriteDesc: Slv4Array (LANES_G-1 downto 0);
  signal rdWriteDesc    : slv       (LANES_G-1 downto 0);
  signal validWriteDesc : slv       (LANES_G-1 downto 0);
  
  signal sAxilReadMaster  : AxiLiteReadMasterType;
  signal sAxilReadSlave   : AxiLiteReadSlaveType;
  signal sAxilWriteMaster : AxiLiteWriteMasterType;
  signal sAxilWriteSlave  : AxiLiteWriteSlaveType;
  
  type RegType is record
    axilWriteSlave : AxiLiteWriteSlaveType;
    axilReadSlave  : AxiLiteReadSlaveType;
    migConfig      : MigConfigArray      (LANES_G-1 downto 0);
    fifoDin        : slv(63 downto 0);
    wrRamAddr      : slv                 (NAPP_C downto 0);
    rdRamAddr      : slv                 (NAPP_C downto 0);
    rdRamAddr_d    : slv                 (NAPP_C downto 0);
    wrDesc         : slv                 (LANES_G-1 downto 0);
    wrDescDin      : slv                 (43 downto 0);
    rdDesc         : slv                 (LANES_G-1 downto 0);
    laneGate       : integer range 0 to LANES_G-1; 
    app            : Slv4Array           (LANES_G-1 downto 0);
    rdTransfer     : slv                 (LANES_G-1 downto 0);
    writeMasters   : AxiStreamMasterArray(LANES_G-1 downto 0); -- command stream
    writeSlaves    : AxiStreamSlaveArray (LANES_G-1 downto 0); -- status stream
    wrBaseAddr     : Slv64Array          (NAPP_C downto 0);
    wrIndex        : Slv12Array          (NAPP_C downto 0);
    loopMode       : slv                 (NAPP_C downto 0);
    axiBusy        : slv                 (LANES_G-1 downto 0);
    axiWriteMaster : AxiWriteMasterArray (LANES_G-1 downto 0); -- Descriptor
    -- Diagnostics control
    monEnable      : sl;
    monSampleInt   : slv                 (15 downto 0);
    monReadoutInt  : slv                 (19 downto 0);
    monBaseAddr    : slv                 (39 downto 0);
    monSample      : sl;
    monSampleCnt   : slv                 (15 downto 0);
    monReadout     : sl;
    monReadoutCnt  : slv                 (19 downto 0);
    usrRst         : slv                 ( 6 downto 0);
  end record;

  constant REG_INIT_C : RegType := (
    axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C,
    axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
    migConfig      => (others=>MIG_CONFIG_INIT_C),
    fifoDin        => (others=>'0'),
    wrRamAddr      => (others=>'0'),
    rdTransfer     => (others=>'0'),
    rdRamAddr      => (others=>'0'),
    rdRamAddr_d    => (others=>'0'),
    wrDesc         => (others=>'0'),
    wrDescDin      => (others=>'0'),
    rdDesc         => (others=>'0'),
    laneGate       => 0,
    app            => (others=>toSlv(NAPP_C,4)),
    writeMasters   => (others=>axiStreamMasterInit(DESC_STREAM_CONFIG_INIT_C)),
    writeSlaves    => (others=>AXI_STREAM_SLAVE_INIT_C),
    wrBaseAddr     => (others=>(others=>'0')),
    wrIndex        => (others=>(others=>'0')),
    loopMode       => (others=>'0'),
    axiBusy        => (others=>'0'),
    axiWriteMaster => (others=>AXI_WRITE_MASTER_INIT_C),
    monEnable      => '0',
    monSampleInt   => toSlv(200,16),     -- 1MHz
    monReadoutInt  => toSlv(1000000,20), -- 1MHz -> 1Hz
    monBaseAddr    => (others=>'0'),
    monSample      => '0',
    monSampleCnt   => (others=>'0'),
    monReadout     => '0',
    monReadoutCnt  => (others=>'0'),
    usrRst         => (others=>'1') );

  signal r   : RegType := REG_INIT_C;
  signal rin : RegType;

  signal monRst     : sl;
  signal monMigStatusMaster : AxiStreamMasterArray(LANES_G-1 downto 0);
  signal monMigStatusSlave  : AxiStreamSlaveArray (LANES_G-1 downto 0);
  signal monWriteDescMaster : AxiStreamMasterArray(NAPP_C-1 downto 0);
  signal monWriteDescSlave  : AxiStreamSlaveArray (NAPP_C-1 downto 0);
  signal monStatus  : slv(8 downto 0);
  
  constant MON_MIG_STATUS_AWIDTH_C : integer := 8;
  constant MON_WRITE_DESC_AWIDTH_C : integer := 8;

  signal iaxiReadMasters  : AxiReadMasterArray (LANES_G-1 downto 0) := (others=>AXI_READ_MASTER_INIT_C);
  signal iaxiWriteMasters : AxiWriteMasterArray(LANES_G-1 downto 0) := (others=>AXI_WRITE_MASTER_INIT_C);
  signal iaxiWriteSlaves  : AxiWriteSlaveArray (LANES_G-1 downto 0) := (others=>AXI_WRITE_SLAVE_INIT_C);
  signal raxiWriteSlave   : AxiWriteSlaveArray (LANES_G-1 downto 0) := (others=>AXI_WRITE_SLAVE_INIT_C);
  signal saxiWriteMasters : AxiWriteMasterArray(LANES_G-1 downto 0) := (others=>AXI_WRITE_MASTER_INIT_C);
  signal usrRstN          : sl;

  signal s2mm_err         : slv(LANES_G-1 downto 0);
  signal mm2s_err         : slv(LANES_G-1 downto 0);
begin

  axiRstN                             <= not axiRst;
  axiReadMasters                      <= iaxiReadMasters;
  usrRst                              <= r.usrRst(0);
  usrRstN                             <= not r.usrRst(0);
  
  U_AxilAsync : entity work.AxiLiteAsync
    port map ( sAxiClk         => axilClk,
               sAxiClkRst      => axilRst,
               sAxiReadMaster  => axilReadMaster,
               sAxiReadSlave   => axilReadSlave,
               sAxiWriteMaster => axilWriteMaster,
               sAxiWriteSlave  => axilWriteSlave,
               mAxiClk         => axiClk,
               mAxiClkRst      => axiRst,
               mAxiReadMaster  => sAxilReadMaster,
               mAxiReadSlave   => sAxilReadSlave,
               mAxiWriteMaster => sAxilWriteMaster,
               mAxiWriteSlave  => sAxilWriteSlave );

  GEN_CHAN : for i in 0 to LANES_G-1 generate

    --
    --  Mux the data write master and the descriptor write master
    --
    U_Mux : entity work.AxiWritePathMux
      generic map ( NUM_SLAVES_G => 2 )
      port map ( axiClk              => axiClk,
                 axiRst              => r.usrRst(0),
                 sAxiWriteMasters(0) => iaxiWriteMasters(i),
                 sAxiWriteMasters(1) => r.axiWriteMaster(i),
                 sAxiWriteSlaves (0) => iaxiWriteSlaves (i),
                 sAxiWriteSlaves (1) => raxiWriteSlave  (i),
                 mAxiWriteMaster     => axiWriteMasters (i),
                 mAxiWriteSlave      => axiWriteSlaves  (i) );
                 
                 
    U_ADM : MigToPcie
      port map ( m_axi_mm2s_aclk            => axiClk,
                 m_axi_mm2s_aresetn         => usrRstN,
                 mm2s_err                   => mm2s_err(i),
                 m_axis_mm2s_cmdsts_aclk    => axiClk,
                 m_axis_mm2s_cmdsts_aresetn => usrRstN,
                 s_axis_mm2s_cmd_tvalid     => intDscReadMasters(i).command.tValid,
                 s_axis_mm2s_cmd_tready     => intDscReadSlaves(i).command .tReady,
                 s_axis_mm2s_cmd_tdata      => intDscReadMasters(i).command.tData(79 DOWNTO 0),
                 m_axis_mm2s_sts_tvalid     => intDscReadSlaves(i) .status.tValid,
                 m_axis_mm2s_sts_tready     => intDscReadMasters(i).status.tReady,
                 m_axis_mm2s_sts_tdata      => intDscReadSlaves(i).status.tData(7 DOWNTO 0),
                 m_axis_mm2s_sts_tkeep      => intDscReadSlaves(i).status.tKeep(0 DOWNTO 0),
                 m_axis_mm2s_sts_tlast      => intDscReadSlaves(i).status.tLast,
                 m_axi_mm2s_arid            => iaxiReadMasters(i).arid(3 downto 0),
                 m_axi_mm2s_araddr          => iaxiReadMasters(i).araddr(37 downto 0),
                 m_axi_mm2s_arlen           => iaxiReadMasters(i).arlen,
                 m_axi_mm2s_arsize          => iaxiReadMasters(i).arsize,
                 m_axi_mm2s_arburst         => iaxiReadMasters(i).arburst,
                 m_axi_mm2s_arprot          => iaxiReadMasters(i).arprot,
                 m_axi_mm2s_arcache         => iaxiReadMasters(i).arcache,
--                 m_axi_mm2s_aruser          => iaxiReadMasters(i).aruser,
                 m_axi_mm2s_arvalid         => iaxiReadMasters(i).arvalid,
                 m_axi_mm2s_arready         => axiReadSlaves(i) .arready,
                 m_axi_mm2s_rdata           => axiReadSlaves(i) .rdata(127 downto 0),
                 m_axi_mm2s_rresp           => axiReadSlaves(i) .rresp,
                 m_axi_mm2s_rlast           => axiReadSlaves(i) .rlast,
                 m_axi_mm2s_rvalid          => axiReadSlaves(i) .rvalid,
                 m_axi_mm2s_rready          => iaxiReadMasters(i).rready,
                 m_axis_mm2s_tdata          => intMasters(i).tData(127 downto 0),
                 m_axis_mm2s_tkeep          => intMasters(i).tKeep( 15 downto 0),
                 m_axis_mm2s_tlast          => intMasters(i).tLast,
                 m_axis_mm2s_tvalid         => intMasters(i).tValid,
                 m_axis_mm2s_tready         => intSlaves(i) .tReady,
                 m_axi_s2mm_aclk            => axiClk,
                 m_axi_s2mm_aresetn         => usrRstN,
                 s2mm_err                   => s2mm_err(i),
                 m_axis_s2mm_cmdsts_awclk   => axiClk,
                 m_axis_s2mm_cmdsts_aresetn => usrRstN,
                 s_axis_s2mm_cmd_tvalid     => r.writeMasters(i).tValid,
                 s_axis_s2mm_cmd_tready     => intDscWriteSlaves(i).command.tReady,
                 s_axis_s2mm_cmd_tdata      => r.writeMasters(i).tData(79 DOWNTO 0),
                 m_axis_s2mm_sts_tvalid     => intDscWriteSlaves(i) .status.tValid,
                 m_axis_s2mm_sts_tready     => intDscWriteMasters(i).status.tReady,
                 m_axis_s2mm_sts_tdata      => intDscWriteSlaves(i) .status.tData(7 DOWNTO 0),
                 m_axis_s2mm_sts_tkeep      => intDscWriteSlaves(i) .status.tKeep(0 DOWNTO 0),
                 m_axis_s2mm_sts_tlast      => intDscWriteSlaves(i) .status.tLast,
                 m_axi_s2mm_awid            => iaxiWriteMasters(i).awid(3 downto 0),
                 m_axi_s2mm_awaddr          => iaxiWriteMasters(i).awaddr(37 downto 0),
                 m_axi_s2mm_awlen           => iaxiWriteMasters(i).awlen,
                 m_axi_s2mm_awsize          => iaxiWriteMasters(i).awsize,
                 m_axi_s2mm_awburst         => iaxiWriteMasters(i).awburst,
                 m_axi_s2mm_awprot          => iaxiWriteMasters(i).awprot,
                 m_axi_s2mm_awcache         => iaxiWriteMasters(i).awcache,
--                 m_axi_s2mm_awuser          => iaxiWriteMasters(i).awuser,
                 m_axi_s2mm_awvalid         => iaxiWriteMasters(i).awvalid,
                 m_axi_s2mm_awready         => iaxiWriteSlaves(i) .awready,
                 m_axi_s2mm_wdata           => iaxiWriteMasters(i).wdata(127 downto 0),
                 m_axi_s2mm_wstrb           => iaxiWriteMasters(i).wstrb( 15 downto 0),
                 m_axi_s2mm_wlast           => iaxiWriteMasters(i).wlast,
                 m_axi_s2mm_wvalid          => iaxiWriteMasters(i).wvalid,
                 m_axi_s2mm_wready          => iaxiWriteSlaves(i) .wready,
                 m_axi_s2mm_bresp           => iaxiWriteSlaves(i) .bresp,
                 m_axi_s2mm_bvalid          => iaxiWriteSlaves(i) .bvalid,
                 m_axi_s2mm_bready          => iaxiWriteMasters(i).bready,
                 s_axis_s2mm_tdata          => intMasters(i).tData(127 downto 0),
                 s_axis_s2mm_tkeep          => intMasters(i).tKeep( 15 downto 0),
                 s_axis_s2mm_tlast          => intMasters(i).tLast,
                 s_axis_s2mm_tvalid         => intMasters(i).tValid,
                 s_axis_s2mm_tready         => intSlaves(i) .tReady
                 );

    --
    --  Keep a (small) FIFO of transfer lengths to attach to write commands
    --

    process ( dscReadMasters, intDscReadSlaves, fullTransfer ) is
    begin
      intDscReadMasters(i)                <= dscReadMasters(i);
      intDscReadMasters(i).command.tValid <= dscReadMasters(i).command.tValid and not fullTransfer(i);
      dscReadSlaves    (i)                <= intDscReadSlaves(i);
    end process;
    
    wrTransfer (i) <= intDscReadMasters(i).command.tValid and intDscReadSlaves(i).command.tReady;
    dinTransfer(i) <= dscReadMasters(i).command.tData(22 downto 0);
    
    U_TransferFifo : entity work.FifoSync
      generic map ( DATA_WIDTH_G => 23,
                    ADDR_WIDTH_G =>  4,
                    FWFT_EN_G    => true )
      port map ( rst        => r.usrRst(0),
                 clk        => axiClk,
                 wr_en      => wrTransfer    (i),
                 din        => dinTransfer   (i),
                 data_count => dcountTransfer(i),
                 rd_en      => rdTransfer    (i),
                 dout       => doutTransfer  (i),
                 valid      => validTransfer (i),
                 full       => fullTransfer  (i));

    U_WriteFifoDesc : entity work.FifoSync
      generic map ( DATA_WIDTH_G => 44,
                    ADDR_WIDTH_G => 4,
                    FWFT_EN_G    => true )
      port map ( rst        => r.usrRst(0),
                 clk        => axiClk,
                 wr_en      => r.wrDesc       (i),
                 din        => r.wrDescDin,
                 data_count => dcountWriteDesc(i),
                 rd_en      => rdWriteDesc    (i),
                 dout       => doutWriteDesc  (i),
                 valid      => validWriteDesc (i));

    GEN_MON_INLET : if i=0 generate
      monRst <= not r.monEnable or r.usrRst(0);
      U_MonMigStatus : entity work.AxisHistogram
        generic map ( ADDR_WIDTH_G => MON_MIG_STATUS_AWIDTH_C,
                      INLET_G      => true )
        port map ( clk  => axiClk,
                   rst  => monRst,
                   wen  => r.monSample,
                   addr => migStatus(i).blocksFree(BLOCK_INDEX_SIZE_C-1 downto BLOCK_INDEX_SIZE_C-8),
                   axisClk => axiClk,
                   axisRst => axiRst,
                   sPush   => r.monReadout,
                   mAxisMaster => monMigStatusMaster(i),
                   mAxisSlave  => monMigStatusSlave (i) );
    end generate;
    GEN_MON_SOCKET : if i>0 generate
      U_MonMigStatus : entity work.AxisHistogram
        generic map ( ADDR_WIDTH_G => MON_MIG_STATUS_AWIDTH_C )
        port map ( clk  => axiClk,
                   rst  => monRst,
                   wen  => r.monSample,
                   addr => migStatus(i).blocksFree(BLOCK_INDEX_SIZE_C-1 downto BLOCK_INDEX_SIZE_C-8),
                   axisClk => axiClk,
                   axisRst => axiRst,
                   sAxisMaster => monMigStatusMaster(i-1),
                   sAxisSlave  => monMigStatusSlave (i-1),
                   mAxisMaster => monMigStatusMaster(i),
                   mAxisSlave  => monMigStatusSlave (i) );
    end generate;
  end generate;

  GEN_APP : for i in 0 to NAPP_C-1 generate
    U_WriteFifoIn : entity work.FifoSync
      generic map ( DATA_WIDTH_G => 64,
                    ADDR_WIDTH_G => 12,
                    FWFT_EN_G    => true )
      port map ( rst        => r.usrRst(0),
                 clk        => axiClk,
                 wr_en      => r.wrRamAddr   (i),
                 din        => r.fifoDin,
                 data_count => dcountRamAddr  (i),
                 rd_en      => rdRamAddr      (i),
                 dout       => doutRamAddr    (i),
                 valid      => validRamAddr   (i) );

    GEN_MON_INLET : if i=0 generate
      U_MonWriteDesc : entity work.AxisHistogram
        generic map ( ADDR_WIDTH_G => MON_WRITE_DESC_AWIDTH_C )
        port map ( clk  => axiClk,
                   rst  => monRst,
                   wen  => r.monSample,
                   addr => dcountRamAddr(i)(11 downto 4),
                   axisClk => axiClk,
                   axisRst => axiRst,
                   sAxisMaster => monMigStatusMaster(LANES_G-1),
                   sAxisSlave  => monMigStatusSlave (LANES_G-1),
                   mAxisMaster => monWriteDescMaster(i),
                   mAxisSlave  => monWriteDescSlave (i) );
    end generate;
    GEN_MON_SOCKET : if i>0 generate
      U_MonWriteDesc : entity work.AxisHistogram
        generic map ( ADDR_WIDTH_G => MON_WRITE_DESC_AWIDTH_C )
        port map ( clk  => axiClk,
                   rst  => monRst,
                   wen  => r.monSample,
                   addr => dcountRamAddr(i)(11 downto 4),
                   axisClk => axiClk,
                   axisRst => axiRst,
                   sAxisMaster => monWriteDescMaster(i-1),
                   sAxisSlave  => monWriteDescSlave (i-1),
                   mAxisMaster => monWriteDescMaster(i),
                   mAxisSlave  => monWriteDescSlave (i) );
    end generate;
  end generate;

  GEN_MON_AXI : entity work.MonToPcieWrapper
    port map ( axiClk          => axiClk,
               axiRst          => r.usrRst(0),
               -- AXI Stream Interface
               sAxisMaster     => monWriteDescMaster(NAPP_C-1),
               sAxisSlave      => monWriteDescSlave (NAPP_C-1),
               -- AXI4 Interface to PCIe
               mAxiWriteMaster => axiWriteMasters(LANES_G),
               mAxiWriteSlave  => axiWriteSlaves (LANES_G),
               -- Configuration
               enable          => r.monEnable,
               mAxiAddr        => r.monBaseAddr,
               -- Status
               ready           => monStatus(8),
               rdIndex         => monStatus(3 downto 0),
               wrIndex         => monStatus(7 downto 4) );

  comb : process ( r, axiRst, 
                   doutTransfer , validTransfer , dcountTransfer ,
                   doutRamAddr  , validRamAddr  , dcountRamAddr  ,
                   doutWriteDesc, validWriteDesc, dcountWriteDesc,
                   intDscWriteSlaves, raxiWriteSlave,
                   migStatus, monStatus, s2mm_err, mm2s_err,
                   sAxilWriteMaster, sAxilReadMaster ) is
      variable v : RegType;
      variable regCon : AxiLiteEndPointType;
      variable regAddr : slv(11 downto 0);
      variable regRst  : sl;
      variable i, app  : integer;
      variable wdata   : slv(63 downto 0);
    begin
      v := r;

      v.rdTransfer  := (others=>'0');
      v.rdRamAddr   := (others=>'0');
      v.wrDesc      := (others=>'0');
      v.wrRamAddr   := (others=>'0');
      v.rdDesc      := (others=>'0');
      
       -- Start transaction block
      axiSlaveWaitTxn(regCon, sAxilWriteMaster, sAxilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      regAddr := toSlv(0,12);
      axiSlaveRegisterR(regCon, regAddr, 0, toSlv(LANES_G,4));
      axiSlaveRegisterR(regCon, regAddr, 4, toSlv(NAPP_C,4));
      axiSlaveRegisterR(regCon, regAddr, 8, toSlv(MON_MIG_STATUS_AWIDTH_C,4));
      axiSlaveRegisterR(regCon, regAddr, 12, toSlv(MON_WRITE_DESC_AWIDTH_C,4));
      regAddr := regAddr + 4;
      regRst  := '0';
      axiWrDetect(regCon, regAddr, regRst);
      regAddr := regAddr + 4;
      axiSlaveRegister(regCon, regAddr, 0, v.monSampleInt);
      regAddr := regAddr + 4;
      axiSlaveRegister(regCon, regAddr, 0, v.monReadoutInt);
      regAddr := regAddr + 4;
      axiSlaveRegister(regCon, regAddr, 0, v.monEnable );
      regAddr := regAddr + 4;
      axiSlaveRegister(regCon, regAddr, 0, v.monBaseAddr(31 downto  0));
      regAddr := regAddr + 4;
      axiSlaveRegister(regCon, regAddr, 0, v.monBaseAddr(39 downto 32));
      regAddr := regAddr + 4;
      axiSlaveRegisterR(regCon, regAddr, 0, v.monSampleCnt);
      regAddr := regAddr + 4;
      axiSlaveRegisterR(regCon, regAddr, 0, v.monReadoutCnt);
      regAddr := regAddr + 4;
      axiSlaveRegisterR(regCon, regAddr, 0, monStatus);

      -- Loop over applications
      --
      --   Push DMA addresses to the FIFOs associated with each application
      for i in 0 to NAPP_C-1 loop
        regAddr := toSlv(i*32+64, 12);
        axiSlaveRegister(regCon, regAddr, 0, v.wrBaseAddr(i)(31 downto  0));
        regAddr := regAddr + 4;
        axiSlaveRegister(regCon, regAddr, 0, v.wrBaseAddr(i)(39 downto 32));
        regAddr := regAddr + 4;
        axiSlaveRegister(regCon, regAddr, 0, v.fifoDin(31 downto 0));
        regAddr := regAddr + 4;
        axiSlaveRegister(regCon, regAddr, 0, v.fifoDin(63 downto 32));
        axiWrDetect     (regCon, regAddr, v.wrRamAddr(i));
        regAddr := regAddr + 4;
        axiSlaveRegisterR(regCon, regAddr, 0, dcountRamAddr(i));
        axiSlaveRegisterR(regCon, regAddr,16, dcountWriteDesc(i));
        regAddr := regAddr + 4;
        axiSlaveRegisterR(regCon, regAddr, 0, r.wrIndex(i));
        regAddr := regAddr + 4;
        axiSlaveRegister (regCon, regAddr, 0, v.loopMode(i));
      end loop;

      for i in 0 to LANES_G-1 loop
        regAddr := toSlv(128+i*32,12);
        axiSlaveRegister(regCon, regAddr, 0, v.app(i));
        regAddr := regAddr + 4;
        axiSlaveRegister(regCon, regAddr, 0, v.migConfig(i).blockSize);
        regAddr := regAddr + 4;
        axiSlaveRegister(regCon, regAddr, 8, v.migConfig(i).blocksPause);
        regAddr := regAddr + 8;
        axiSlaveRegisterR(regCon, regAddr, 0, dcountTransfer (i));
        regAddr := regAddr + 4;
        axiSlaveRegisterR(regCon, regAddr, 0, migStatus(i).blocksFree);
        axiSlaveRegisterR(regCon, regAddr,29, mm2s_err(i));
        axiSlaveRegisterR(regCon, regAddr,30, s2mm_err(i));
        axiSlaveRegisterR(regCon, regAddr,31, migStatus(i).memReady);
      end loop;

      -- End transaction block
      axiSlaveDefault(regCon, v.axilWriteSlave, v.axilReadSlave, AXI_ERROR_RESP_G);

      sAxilWriteSlave <= r.axilWriteSlave;
      sAxilReadSlave  <= r.axilReadSlave;

      if regRst = '1' then
        v.usrRst := (others=>'1');
      else
        v.usrRst := '0' & r.usrRst(r.usrRst'left downto 1);
      end if;

      -- Loop over lanes
      for i in 0 to LANES_G-1 loop
        v.axiWriteMaster(i).bready := '1';
        
        if intDscWriteSlaves(i).command.tReady = '1' then
          v.writeMasters(i).tValid := '0';
        end if;
        
        if r.writeSlaves(i).tReady = '1' then
          v.writeSlaves(i).tReady := '0';
        end if;
      end loop;

      --   Serialize access to the application FIFOs
      --  Allocate each clock to one lane's arbitration
      i          := r.laneGate;
      app        := conv_integer(r.app(i));
      if r.laneGate = LANES_G-1 then
        v.laneGate := 0;
      else
        v.laneGate := r.laneGate+1;
      end if;

      --   Queue the write address to the data mover engine when a new
      --   transfer is waiting and a target buffer is available.
      if (v.writeMasters(i).tValid = '0' and
          validTransfer(i) = '1' and
          validRamAddr(app) = '1') then
        v.writeMasters(i).tValid := '1';
        v.writeMasters(i).tLast  := '1';
        v.writeMasters(i).tData(79 downto 0) := x"0" & toSlv(app,4) &
                                                doutRamAddr(app)(39 downto 0) &
                                                "01" & toSlv(0,6) &
                                                '1' & doutTransfer(i);
        v.rdTransfer(i) := '1';
        v.rdRamAddr(app) := '1';
        v.wrDescDin(43 downto 20) := '0' & doutTransfer(i);
        v.wrDescDin(19 downto  0) := doutRamAddr(app)(59 downto 40);
        v.wrDesc   (i) := '1';

        if r.loopMode(app) = '1' then
          v.fifoDin        := doutRamAddr(app);
          v.wrRamAddr(app) := '1';
        end if;
      end if;

      for j in 0 to LANES_G-1 loop
        --  Reset strobing signals
        if raxiWriteSlave(j).awready = '1' then
          v.axiWriteMaster(j).awvalid := '0';
        end if;

        if raxiWriteSlave(j).wready = '1' then
          v.axiWriteMaster(j).wvalid  := '0';
          v.axiWriteMaster(j).wlast   := '0';
        end if;

        if (v.axiWriteMaster(j).awvalid = '0' and
            v.axiWriteMaster(j).wvalid = '0' and
            raxiWriteSlave  (j).bvalid = '1') then
          v.axiBusy(j) := '0';
        end if;
      end loop;
      
      --  Translate the write status to a descriptor axi write
      if r.axiBusy(i) = '0' then
        if (intDscWriteSlaves(i).status.tValid = '1' and
            validWriteDesc(i) = '1') then
          -- Write address channel
          v.axiWriteMaster(i).awaddr := r.wrBaseAddr(app) + (r.wrIndex(app) & "000");
          v.axiWriteMaster(i).awlen  := x"00";  -- Single transaction
          v.axiWriteMaster(i).awsize := toSlv(4,3); -- 16 byte bus

          -- Write data channel
          v.axiWriteMaster(i).wlast := '1';
          if r.wrIndex(app)(0) = '0' then
            v.axiWriteMaster(i).wstrb := resize(x"00FF", 128);
          else
            v.axiWriteMaster(i).wstrb := resize(x"FF00", 128);
          end if;
          
          -- Descriptor data
          wdata(63 downto 56) := toSlv(i,3) & toSlv(0,5); -- vc
          wdata(55 downto 32) := doutWriteDesc(i)(43 downto 20);
          wdata(31 downto 28) := toSlv(0,4); -- firstUser
          wdata(27 downto 24) := toSlv(0,4); -- lastUser
          wdata(23 downto 4)  := doutWriteDesc(i)(19 downto 0);
          wdata(3)            := '0'; -- continue
          wdata(2 downto 0)   := intDscWriteSlaves(i).status.tData(7 downto 5);

          v.axiWriteMaster(i).wdata(127 downto 64) := wdata;
          v.axiWriteMaster(i).wdata( 63 downto  0) := wdata;
          
          v.axiWriteMaster(i).awvalid := '1';
          v.axiWriteMaster(i).awcache := x"3";
          v.axiWriteMaster(i).awburst := "01";
          v.axiWriteMaster(i).wvalid  := '1';
          v.wrIndex(app)              := r.wrIndex(app) + 1;
          v.axiBusy       (i)         := '1';

          v.rdDesc        (i)         := '1';
          v.writeSlaves(i).tReady     := '1';
        end if;
      end if;

      v.monSample  := '0';
      v.monReadout := '0';

      if r.monEnable = '1' then
        if r.monSampleCnt = r.monSampleInt then
          v.monSample    := '1';
          v.monSampleCnt := (others=>'0');
        else
          v.monSampleCnt := r.monSampleCnt + 1;
        end if;
        if r.monSample = '1' then
          if r.monReadoutCnt = r.monReadoutInt then
            v.monReadout    := '1';
            v.monReadoutCnt := (others=>'0');
          else
            v.monReadoutCnt := r.monReadoutCnt + 1;
          end if;
        end if;
      else
        v.monSampleCnt  := (others=>'0');
        v.monReadoutCnt := (others=>'0');
      end if;

      --
      --  Assign these before the reset processing
      --
      for i in 0 to LANES_G-1 loop
        intDscWriteMasters(i).command <= r.writeMasters(i);
        intDscWriteMasters(i).status  <= v.writeSlaves(i);
      end loop;

      rdTransfer  <= v.rdTransfer;
      rdRamAddr   <= v.rdRamAddr;
      rdWriteDesc <= v.rdDesc;

      if axiRst = '1' then
        v := REG_INIT_C;
      end if;
      
      rin <= v;

      migConfig <= r.migConfig;
      
    end process comb;

    seq: process(axiClk) is
    begin
      if rising_edge(axiClk) then
        r <= rin;
      end if;
    end process seq;
            
      
 end mapping;



