-------------------------------------------------------------------------------
-- File       : PgpLane.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2018-03-04
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'SLAC PGP Gen3 Card'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC PGP Gen3 Card', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.AxiPciePkg.all;
use work.Pgp3Pkg.all;

entity PgpLane is
   generic (
      TPD_G            : time             := 1 ns;
      LANE_G           : natural          := 0;
      NUM_VC_G         : positive         := 16;
      AXI_ERROR_RESP_G : slv(1 downto 0)  := AXI_RESP_DECERR_C;
      AXI_BASE_ADDR_G  : slv(31 downto 0) := (others => '0'));
   port (
      -- QPLL Interface
      qpllLock        : in  slv(1 downto 0);
      qpllClk         : in  slv(1 downto 0);
      qpllRefclk      : in  slv(1 downto 0);
      qpllRst         : out slv(1 downto 0);
      -- PGP Serial Ports
      pgpTxP          : out sl;
      pgpTxN          : out sl;
      pgpRxP          : in  sl;
      pgpRxN          : in  sl;
      -- DMA Interface (dmaClk domain)
      dmaClk          : out sl;
      dmaRst          : out sl;
      dmaObMaster     : in  AxiStreamMasterType;
      dmaObSlave      : out AxiStreamSlaveType;
      dmaIbMaster     : out AxiStreamMasterType;
      dmaIbSlave      : in  AxiStreamSlaveType;
      dmaIbFull       : in  sl;
       -- OOB Signals (dmaClk domain)
      txOpCodeEn      : in  sl;
      txOpCode        : in  slv(7 downto 0);
      rxOpCodeEn      : out sl;
      rxOpCode        : out slv(7 downto 0);
     -- AXI-Lite Interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end PgpLane;

architecture mapping of PgpLane is

   constant NUM_AXI_MASTERS_C : natural := 4;

   constant MISC_INDEX_C   : natural := 0;
   constant RX_MON_INDEX_C : natural := 1;
   constant TX_MON_INDEX_C : natural := 2;
   constant PGP_INDEX_C    : natural := 3;

   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := (
      MISC_INDEX_C    => (
         baseAddr     => (AXI_BASE_ADDR_G+x"0000_0000"),
         addrBits     => 12,
         connectivity => x"FFFF"),
      RX_MON_INDEX_C  => (
         baseAddr     => (AXI_BASE_ADDR_G+x"0000_1000"),
         addrBits     => 12,
         connectivity => x"FFFF"),
      TX_MON_INDEX_C  => (
         baseAddr     => (AXI_BASE_ADDR_G+x"0000_2000"),
         addrBits     => 12,
         connectivity => x"FFFF"),
      PGP_INDEX_C     => (
         baseAddr     => (AXI_BASE_ADDR_G+x"0000_8000"),
         addrBits     => 15,
         connectivity => x"FFFF"));

   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);

   signal pgpClk : sl;
   signal pgpRst : sl;

   signal pgpTxOut     : Pgp3TxOutType;
   signal pgpTxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal pgpTxSlaves  : AxiStreamSlaveArray(NUM_VC_G-1 downto 0);

   signal rxMasters    : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal pgpRxCtrl    : AxiStreamCtrlArray(NUM_VC_G-1 downto 0);

   signal pgpRxVcBlowoff : slv(15 downto 0);

   signal pgpTxIn      : Pgp3TxInType  := PGP3_TX_IN_INIT_C;
   signal pgpRxIn      : Pgp3RxInType  := PGP3_RX_IN_INIT_C;
   signal pgpRxOut     : Pgp3RxOutType;

   signal pgpRxIn_frameDrop  : sl;
   signal pgpRxIn_frameTrunc : sl;
begin

   dmaClk <= pgpClk;
   dmaRst <= pgpRst;

   rxOpCodeEn  <= pgpRxOut.opCodeEn;
   rxOpCode    <= pgpRxOut.opCodeData(7 downto 0);
   
   ---------------------
   -- AXI-Lite Crossbar
   ---------------------
   U_XBAR : entity work.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         DEC_ERROR_RESP_G   => AXI_ERROR_RESP_G,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXI_MASTERS_C,
         MASTERS_CONFIG_G   => AXI_CONFIG_C)
      port map (
         axiClk              => axilClk,
         axiClkRst           => axilRst,
         sAxiWriteMasters(0) => axilWriteMaster,
         sAxiWriteSlaves(0)  => axilWriteSlave,
         sAxiReadMasters(0)  => axilReadMaster,
         sAxiReadSlaves(0)   => axilReadSlave,
         mAxiWriteMasters    => axilWriteMasters,
         mAxiWriteSlaves     => axilWriteSlaves,
         mAxiReadMasters     => axilReadMasters,
         mAxiReadSlaves      => axilReadSlaves);

   -----------
   -- PGP Core
   -----------
   U_Pgp : entity work.Pgp3GthUs
      generic map (
         TPD_G             => TPD_G,
         NUM_VC_G          => NUM_VC_G,
         AXIL_CLK_FREQ_G   => (SYS_CLK_FREQ_C/2.0),
         AXIL_BASE_ADDR_G  => AXI_CONFIG_C(PGP_INDEX_C).baseAddr,
         AXIL_ERROR_RESP_G => AXI_ERROR_RESP_G)
      port map (
         -- Stable Clock and Reset
         stableClk       => axilClk,
         stableRst       => axilRst,
         -- QPLL Interface
         qpllLock        => qpllLock,
         qpllClk         => qpllClk,
         qpllRefclk      => qpllRefclk,
         qpllRst         => qpllRst,
         -- Gt Serial IO
         pgpGtTxP        => pgpTxP,
         pgpGtTxN        => pgpTxN,
         pgpGtRxP        => pgpRxP,
         pgpGtRxN        => pgpRxN,
         -- Clocking
         pgpClk          => pgpClk,
         pgpClkRst       => pgpRst,
         -- Non VC Rx Signals
         pgpRxIn         => pgpRxIn,
         pgpRxOut        => pgpRxOut,
         -- Non VC Tx Signals
         pgpTxIn         => PGP3_TX_IN_INIT_C,
         pgpTxOut        => pgpTxOut,
         -- Frame Transmit Interface
         pgpTxMasters    => pgpTxMasters,
         pgpTxSlaves     => pgpTxSlaves,
         -- Frame Receive Interface
         pgpRxMasters    => pgpRxMasters,
         pgpRxCtrl       => pgpRxCtrl,
         -- AXI-Lite Register Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(PGP_INDEX_C),
         axilReadSlave   => axilReadSlaves(PGP_INDEX_C),
         axilWriteMaster => axilWriteMasters(PGP_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(PGP_INDEX_C));

   --------------
   -- PGP TX Path
   --------------
   U_Tx : entity work.PgpLaneTx
      generic map (
         TPD_G    => TPD_G,
         NUM_VC_G => NUM_VC_G)
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk       => pgpClk,
         dmaRst       => pgpRst,
         dmaObMaster  => dmaObMaster,
         dmaObSlave   => dmaObSlave,
         -- PGP Interface
         pgpClk       => pgpClk,
         pgpRst       => pgpRst,
         pgpRxOut     => pgpRxOut,
         pgpTxOut     => pgpTxOut,
         pgpTxMasters => pgpTxMasters,
         pgpTxSlaves  => pgpTxSlaves);

   -----------------------         
   -- RX VC Blowoff Filter
   -----------------------         
   BLOWOFF_FILTER : process (pgpRxMasters, pgpRxOut, pgpRxVcBlowoff) is
      variable tmp : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
      variable i   : natural;
   begin
      tmp := pgpRxMasters;
      for i in NUM_VC_G-1 downto 0 loop
         if (pgpRxVcBlowoff(i) = '1') or (pgpRxOut.linkReady = '0') then
            tmp(i).tValid := '0';
         end if;
      end loop;
      rxMasters <= tmp;
   end process;

   --------------
   -- PGP RX Path
   --------------
   U_Rx : entity work.PgpLaneRx
      generic map (
         TPD_G    => TPD_G,
         LANE_G   => LANE_G,
         NUM_VC_G => NUM_VC_G)
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk       => pgpClk,
         dmaRst       => pgpRst,
         dmaIbMaster  => dmaIbMaster,
         dmaIbSlave   => dmaIbSlave,
         dmaIbFull    => dmaIbFull,
         frameDrop    => pgpRxIn_frameDrop,
         frameTrunc   => pgpRxIn_frameTrunc,
         -- PGP RX Interface (pgpRxClk domain)
         pgpClk       => pgpClk,
         pgpRst       => pgpRst,
         pgpRxMasters => rxMasters,
         pgpRxCtrl    => pgpRxCtrl);

   -----------
   -- PGP MISC
   -----------
   U_Misc : entity work.PgpLaneMisc
      generic map (
         TPD_G            => TPD_G,
         AXI_ERROR_RESP_G => AXI_ERROR_RESP_G)
      port map (
         pgpClk          => pgpClk,
         pgpRst          => pgpRst,
         pgpRxVcBlowoff  => pgpRxVcBlowoff,
         pgpRxLoopback   => pgpRxIn.loopback,
         pgpRxReset      => pgpRxIn.resetRx,
         pgpFrameDrop    => pgpRxIn_frameDrop,
         pgpFrameTrunc   => pgpRxIn_frameTrunc,
         -- AXI-Lite Register Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters(MISC_INDEX_C),
         axilReadSlave   => axilReadSlaves(MISC_INDEX_C),
         axilWriteMaster => axilWriteMasters(MISC_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(MISC_INDEX_C));

   --------------------------------
   -- Monitor the PGP RX VC streams
   --------------------------------
   LANE_MON_RX : entity work.AxiStreamMonAxiL
      generic map(
         TPD_G            => TPD_G,
         COMMON_CLK_G     => false,
         AXIS_CLK_FREQ_G  => 156.25E+6,
         AXIS_NUM_SLOTS_G => NUM_VC_G,
         AXIS_CONFIG_G    => PGP3_AXIS_CONFIG_C)
      port map(
         -- AXIS Stream Interface
         axisClk          => pgpClk,
         axisRst          => pgpRst,
         axisMaster       => pgpRxMasters,
         axisSlave        => (others => AXI_STREAM_SLAVE_FORCE_C),  -- TREADY not used in PGP RX path
         -- AXI lite slave port for register access
         axilClk          => axilClk,
         axilRst          => axilRst,
         sAxilWriteMaster => axilWriteMasters(RX_MON_INDEX_C),
         sAxilWriteSlave  => axilWriteSlaves(RX_MON_INDEX_C),
         sAxilReadMaster  => axilReadMasters(RX_MON_INDEX_C),
         sAxilReadSlave   => axilReadSlaves(RX_MON_INDEX_C));

   --------------------------------
   -- Monitor the PGP TX VC streams
   --------------------------------
   LANE_MON_TX : entity work.AxiStreamMonAxiL
      generic map(
         TPD_G            => TPD_G,
         COMMON_CLK_G     => false,
         AXIS_CLK_FREQ_G  => 156.25E+6,
         AXIS_NUM_SLOTS_G => NUM_VC_G,
         AXIS_CONFIG_G    => PGP3_AXIS_CONFIG_C)
      port map(
         -- AXIS Stream Interface
         axisClk          => pgpClk,
         axisRst          => pgpRst,
         axisMaster       => pgpTxMasters,
         axisSlave        => pgpTxSlaves,
         -- AXI lite slave port for register access
         axilClk          => axilClk,
         axilRst          => axilRst,
         sAxilWriteMaster => axilWriteMasters(TX_MON_INDEX_C),
         sAxilWriteSlave  => axilWriteSlaves(TX_MON_INDEX_C),
         sAxilReadMaster  => axilReadMasters(TX_MON_INDEX_C),
         sAxilReadSlave   => axilReadSlaves(TX_MON_INDEX_C));

   U_TxOpCode : entity work.SynchronizerFifo
     generic map ( DATA_WIDTH_G => 8,
                   ADDR_WIDTH_G => 2 )
     port map ( rst    => pgpRst,
                wr_clk => pgpClk,
                wr_en  => txOpCodeEn,
                din    => txOpCode,
                rd_clk => pgpClk,
                valid  => pgpTxIn.opCodeEn,
                dout   => pgpTxIn.opCodeData(7 downto 0) );
   pgpTxIn.opCodeNumber <= toSlv(1,3);

end mapping;
