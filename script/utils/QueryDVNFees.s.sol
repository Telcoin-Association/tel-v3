// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";

interface ILayerZeroDVN {
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view returns (uint256 fee);
}

/// @title QueryDVNFees
/// @notice Queries getFee() on all candidate DVN contracts for every pathway Telcoin needs.
///         Outputs a fee comparison table in the console.
///
/// ## How to Run
///
/// Query fees from Ethereum (source) to Base + Polygon:
/// ```
/// forge script script/utils/QueryDVNFees.s.sol --rpc-url $ETHEREUM_RPC_URL -vvvv
/// ```
///
/// Query fees from Base (source) to Ethereum + Polygon:
/// ```
/// forge script script/utils/QueryDVNFees.s.sol --rpc-url $BASE_RPC_URL -vvvv
/// ```
///
/// Query fees from Polygon (source) to Ethereum + Base:
/// ```
/// forge script script/utils/QueryDVNFees.s.sol --rpc-url $POLYGON_RPC_URL -vvvv
/// ```
contract QueryDVNFees is Script {
    // ----------------
    // LZ Endpoint IDs
    // ----------------

    uint32 constant ETH_EID = 30101;
    uint32 constant BASE_EID = 30184;
    uint32 constant POLYGON_EID = 30109;

    // -----------------
    // Block Confirmations (standard for OFT)
    // -----------------

    uint64 constant CONFIRMATIONS = 15;

    // -------------------------
    // DVN Addresses (Ethereum)
    // -------------------------

    address constant ETH_LZ          = 0xDb979D0A36aF0525AFa60Fc265B1525505c55D79;
    address constant ETH_NETHERMIND  = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
    address constant ETH_CANARY     = 0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd;
    address constant ETH_DTAG       = 0x373a6E5c0C4E89E24819f00AA37ea370917AAfF4;
    address constant ETH_FCAT       = 0xc61aF5706b80Ca941a0aAb1C7B3D7a953E4dD8C4;
    address constant ETH_LUGANODES  = 0x58249a2Ec05c1978bF21DF1f5eC1847e42455CF4;
    address constant ETH_P2P        = 0x06559EE34D85a88317Bf0bfE307444116c631b67;
    address constant ETH_NANSEN     = 0x3a4636E9AB975d28d3Af808b4e1c9fd936374E30;

    // -------------------------
    // DVN Addresses (Base)
    // -------------------------

    address constant BASE_LZ         = 0x9e059a54699a285714207b43B055483E78FAac25;
    address constant BASE_NETHERMIND = 0x658947BC7956aea0067a62Cf87ab02ae199Ef3f3;
    address constant BASE_CANARY    = 0x554833698Ae0FB22ECC90B01222903fD62CA4B47;
    address constant BASE_DTAG      = 0xc2A0C36f5939A14966705c7Cec813163FaEEa1F0;
    address constant BASE_FCAT      = 0xEaE72C81F3FCe1313EeeE26717F42af91E178516;
    address constant BASE_LUGANODES = 0xa0AF56164F02bDf9d75287ee77c568889F11d5f2;
    address constant BASE_P2P       = 0x5b6735c66d97479cCD18294fc96B3084EcB2fa3f;
    address constant BASE_NANSEN    = 0x93aC538152E1BC4F093aE5666Ee9FD1d84f4f4bF;

    // -------------------------
    // DVN Addresses (Polygon)
    // -------------------------

    address constant POLY_LZ         = 0xA70C51C38D5A9990F3113a403D74EBa01fce4CCb;
    address constant POLY_NETHERMIND = 0xbCefdAdB8d24b1d36c26B522235012Cd4cf162f6;
    address constant POLY_CANARY    = 0x13feb7234Ff60A97af04477d6421415766753Ba3;
    address constant POLY_DTAG      = 0x5CcCb8DE6Cdba9D2Af9d84465653af7390FDf9Dd;
    address constant POLY_FCAT      = 0x14206011d192E4F41D694d21ac599D0e88c2c12A;
    address constant POLY_LUGANODES = 0xD1b5493e712081A6FBAb73116405590046668F6b;
    address constant POLY_P2P       = 0x9EEee79F5dBC4D99354b5CB547c138Af432F937b;
    address constant POLY_NANSEN    = 0x0a8618F71dB88AB5D0CAF0610Ede19F0AB8817c5;

    // ------
    // Types
    // ------

    struct DVNInfo {
        string name;
        address addr;
    }

    struct ChainInfo {
        string name;
        uint32 eid;
    }

    function run() public view {
        // Detect which chain we're on and set up DVNs + destinations
        DVNInfo[] memory dvns;
        ChainInfo[] memory destinations;
        string memory sourceName;

        if (block.chainid == 1) {
            sourceName = "Ethereum";
            dvns = _ethDVNs();
            destinations = new ChainInfo[](2);
            destinations[0] = ChainInfo("Base", BASE_EID);
            destinations[1] = ChainInfo("Polygon", POLYGON_EID);
        } else if (block.chainid == 8453) {
            sourceName = "Base";
            dvns = _baseDVNs();
            destinations = new ChainInfo[](2);
            destinations[0] = ChainInfo("Ethereum", ETH_EID);
            destinations[1] = ChainInfo("Polygon", POLYGON_EID);
        } else if (block.chainid == 137) {
            sourceName = "Polygon";
            dvns = _polyDVNs();
            destinations = new ChainInfo[](2);
            destinations[0] = ChainInfo("Ethereum", ETH_EID);
            destinations[1] = ChainInfo("Base", BASE_EID);
        } else {
            revert("Unsupported chain. Run on Ethereum (1), Base (8453), or Polygon (137)");
        }

        console.log("==============================================");
        console.log("  DVN Fee Query - Source: %s (chain %s)", sourceName, vm.toString(block.chainid));
        console.log("==============================================");
        console.log("");

        // Use a dummy sender address (fees typically don't vary by sender for standard OFTs)
        address sender = address(0xdead);
        bytes memory options = "";

        for (uint256 d; d < destinations.length; d++) {
            console.log("--- Pathway: %s -> %s (EID %s) ---", sourceName, destinations[d].name, vm.toString(uint256(destinations[d].eid)));
            console.log("");
            console.log("  %-20s %18s %18s", "DVN Provider", "Fee (wei)", "Fee (ETH/native)");
            console.log("  %-20s %18s %18s", "--------------------", "------------------", "------------------");

            uint256 totalFee;
            uint256 successCount;

            for (uint256 i; i < dvns.length; i++) {
                try ILayerZeroDVN(dvns[i].addr).getFee(
                    destinations[d].eid,
                    CONFIRMATIONS,
                    sender,
                    options
                ) returns (uint256 fee) {
                    string memory feeEth = _formatEther(fee);
                    console.log("  %-20s %18s %18s", dvns[i].name, vm.toString(fee), feeEth);
                    totalFee += fee;
                    successCount++;
                } catch {
                    console.log("  %-20s %18s", dvns[i].name, "QUERY FAILED");
                }
            }

            console.log("");
            if (successCount > 0) {
                console.log("  Total (all %s DVNs):  %s wei  (%s native)", vm.toString(successCount), vm.toString(totalFee), _formatEther(totalFee));
                console.log("  Average per DVN:     %s wei  (%s native)", vm.toString(totalFee / successCount), _formatEther(totalFee / successCount));
            }
            console.log("");
        }
    }

    // -------
    // Helpers
    // -------

    function _formatEther(uint256 wei_) internal pure returns (string memory) {
        uint256 whole = wei_ / 1e18;
        uint256 frac = (wei_ % 1e18) / 1e12; // 6 decimal places
        // Simple formatting - shows whole.fraction
        if (frac == 0) {
            return string.concat(vm.toString(whole), ".000000");
        }
        // Pad fraction to 6 digits
        string memory fracStr = vm.toString(frac);
        bytes memory padded = new bytes(6);
        bytes memory fracBytes = bytes(fracStr);
        uint256 padLen = 6 - fracBytes.length;
        for (uint256 i; i < 6; i++) {
            if (i < padLen) padded[i] = "0";
            else padded[i] = fracBytes[i - padLen];
        }
        return string.concat(vm.toString(whole), ".", string(padded));
    }

    function _ethDVNs() internal pure returns (DVNInfo[] memory dvns) {
        dvns = new DVNInfo[](8);
        dvns[0] = DVNInfo("LayerZero Labs", ETH_LZ);
        dvns[1] = DVNInfo("Nethermind", ETH_NETHERMIND);
        dvns[2] = DVNInfo("Canary", ETH_CANARY);
        dvns[3] = DVNInfo("Deutsche Telekom", ETH_DTAG);
        dvns[4] = DVNInfo("FCAT", ETH_FCAT);
        dvns[5] = DVNInfo("Luganodes", ETH_LUGANODES);
        dvns[6] = DVNInfo("P2P", ETH_P2P);
        dvns[7] = DVNInfo("Nansen", ETH_NANSEN);
    }

    function _baseDVNs() internal pure returns (DVNInfo[] memory dvns) {
        dvns = new DVNInfo[](8);
        dvns[0] = DVNInfo("LayerZero Labs", BASE_LZ);
        dvns[1] = DVNInfo("Nethermind", BASE_NETHERMIND);
        dvns[2] = DVNInfo("Canary", BASE_CANARY);
        dvns[3] = DVNInfo("Deutsche Telekom", BASE_DTAG);
        dvns[4] = DVNInfo("FCAT", BASE_FCAT);
        dvns[5] = DVNInfo("Luganodes", BASE_LUGANODES);
        dvns[6] = DVNInfo("P2P", BASE_P2P);
        dvns[7] = DVNInfo("Nansen", BASE_NANSEN);
    }

    function _polyDVNs() internal pure returns (DVNInfo[] memory dvns) {
        dvns = new DVNInfo[](8);
        dvns[0] = DVNInfo("LayerZero Labs", POLY_LZ);
        dvns[1] = DVNInfo("Nethermind", POLY_NETHERMIND);
        dvns[2] = DVNInfo("Canary", POLY_CANARY);
        dvns[3] = DVNInfo("Deutsche Telekom", POLY_DTAG);
        dvns[4] = DVNInfo("FCAT", POLY_FCAT);
        dvns[5] = DVNInfo("Luganodes", POLY_LUGANODES);
        dvns[6] = DVNInfo("P2P", POLY_P2P);
        dvns[7] = DVNInfo("Nansen", POLY_NANSEN);
    }
}
