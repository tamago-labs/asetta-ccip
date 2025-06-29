// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {BurnMintTokenPool, TokenPool} from "@chainlink/contracts-ccip/contracts/pools/BurnMintTokenPool.sol";
import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import "../src/RWAToken.sol";
import {console} from "forge-std/console.sol";
 

contract RWATokenTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    RWAToken public rwaTokenEthSepolia;
    RWAToken public rwaTokenAvalancheFuji;
    RWAToken public rwaTokenArbitrumSepolia;
    
    BurnMintTokenPool public burnMintTokenPoolEthSepolia;
    BurnMintTokenPool public burnMintTokenPoolAvalancheFuji;
    BurnMintTokenPool public burnMintTokenPoolArbitrumSepolia;

    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails avalancheFujiNetworkDetails;
    Register.NetworkDetails arbitrumSepoliaNetworkDetails;

    uint256 ethSepoliaFork;
    uint256 avalancheFujiFork;
    uint256 arbitrumSepoliaFork;

    address alice;

    function setUp() public {
        alice = makeAddr("alice");

        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory AVALANCHE_FUJI_RPC_URL = vm.envString("AVALANCHE_FUJI_RPC_URL");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        ethSepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        avalancheFujiFork = vm.createFork(AVALANCHE_FUJI_RPC_URL);
        arbitrumSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        RWAToken.AssetMetadata memory metadata = RWAToken.AssetMetadata({
            assetType: "real-estate",
            description: "Luxury apartment building in NYC",
            totalValue: 50_000_000 * 1e8, // $50M with 8 decimals
            url: "https://example.com/property",
            createdAt: 0 // Will be set by contract
        });
 

        // Step 1) Deploy RWA token on Ethereum Sepolia
        vm.startPrank(alice);
        rwaTokenEthSepolia = new RWAToken(
            "NYC Real Estate Token",
            "NYCRE",
            metadata
        );
        vm.stopPrank();
 

        // Step 2) Deploy RWA token on Avalanche Fuji
        vm.selectFork(avalancheFujiFork);

        vm.startPrank(alice);
        rwaTokenAvalancheFuji = new RWAToken(
            "NYC Real Estate Token",
            "NYCRE",
            metadata
        );
        vm.stopPrank();
 

        // Step 3) Deploy RWA token on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);

        vm.startPrank(alice);
        rwaTokenArbitrumSepolia = new RWAToken(
            "NYC Real Estate Token",
            "NYCRE",
            metadata
        );
        vm.stopPrank();
    }

    function test_forkSupportNewRWAToken() public {
  
        // Step 4) Deploy BurnMintTokenPool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        address[] memory allowlist = new address[](0);
        uint8 localTokenDecimals = 18;

        vm.startPrank(alice);
        burnMintTokenPoolEthSepolia = new BurnMintTokenPool(
            IBurnMintERC20(address(rwaTokenEthSepolia)),
            localTokenDecimals,
            allowlist,
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();
 
        // Step 5) Deploy BurnMintTokenPool on Avalanche Fuji
        vm.selectFork(avalancheFujiFork);
        avalancheFujiNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(alice);
        burnMintTokenPoolAvalancheFuji = new BurnMintTokenPool(
            IBurnMintERC20(address(rwaTokenAvalancheFuji)),
            localTokenDecimals,
            allowlist,
            avalancheFujiNetworkDetails.rmnProxyAddress,
            avalancheFujiNetworkDetails.routerAddress
        );
        vm.stopPrank();
 
        // Step 6) Deploy BurnMintTokenPool on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);
        arbitrumSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(alice);
        burnMintTokenPoolArbitrumSepolia = new BurnMintTokenPool(
            IBurnMintERC20(address(rwaTokenArbitrumSepolia)),
            localTokenDecimals,
            allowlist,
            arbitrumSepoliaNetworkDetails.rmnProxyAddress,
            arbitrumSepoliaNetworkDetails.routerAddress
        );
        vm.stopPrank();
 

        // Step 7) Grant Mint and Burn roles to BurnMintTokenPool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        vm.startPrank(alice);
        rwaTokenEthSepolia.grantRole(rwaTokenEthSepolia.MINTER_ROLE(), address(burnMintTokenPoolEthSepolia));
        rwaTokenEthSepolia.grantRole(rwaTokenEthSepolia.BURNER_ROLE(), address(burnMintTokenPoolEthSepolia));
        vm.stopPrank();
 
        // Step 8) Grant Mint and Burn roles to BurnMintTokenPool on Avalanche Fuji
        vm.selectFork(avalancheFujiFork);

        vm.startPrank(alice);
        rwaTokenAvalancheFuji.grantRole(
            rwaTokenAvalancheFuji.MINTER_ROLE(), address(burnMintTokenPoolAvalancheFuji)
        );
        rwaTokenAvalancheFuji.grantRole(
            rwaTokenAvalancheFuji.BURNER_ROLE(), address(burnMintTokenPoolAvalancheFuji)
        );
        vm.stopPrank();
 
        // Step 9) Grant Mint and Burn roles to BurnMintTokenPool on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);

        vm.startPrank(alice);
        rwaTokenArbitrumSepolia.grantRole(
            rwaTokenArbitrumSepolia.MINTER_ROLE(), address(burnMintTokenPoolArbitrumSepolia)
        );
        rwaTokenArbitrumSepolia.grantRole(
            rwaTokenArbitrumSepolia.BURNER_ROLE(), address(burnMintTokenPoolArbitrumSepolia)
        );
        vm.stopPrank();
 
        // Step 10) Claim Admin role on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        RegistryModuleOwnerCustom registryModuleOwnerCustomEthSepolia =
            RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress);

        vm.startPrank(alice);
        registryModuleOwnerCustomEthSepolia.registerAdminViaGetCCIPAdmin(address(rwaTokenEthSepolia));
        vm.stopPrank();

        // Step 11) Claim Admin role on Avalanche Fuji
        vm.selectFork(avalancheFujiFork);

        RegistryModuleOwnerCustom registryModuleOwnerCustomAvalancheFuji =
            RegistryModuleOwnerCustom(avalancheFujiNetworkDetails.registryModuleOwnerCustomAddress);

        vm.startPrank(alice);
        registryModuleOwnerCustomAvalancheFuji.registerAdminViaGetCCIPAdmin(address(rwaTokenAvalancheFuji));
        vm.stopPrank();

        // Step 12) Claim Admin role on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);

        RegistryModuleOwnerCustom registryModuleOwnerCustomArbitrumSepolia =
            RegistryModuleOwnerCustom(arbitrumSepoliaNetworkDetails.registryModuleOwnerCustomAddress);

        vm.startPrank(alice);
        registryModuleOwnerCustomArbitrumSepolia.registerAdminViaGetCCIPAdmin(address(rwaTokenArbitrumSepolia));
        vm.stopPrank();
 

        // Step 13) Accept Admin role on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        TokenAdminRegistry tokenAdminRegistryEthSepolia =
            TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress);

        vm.startPrank(alice);
        tokenAdminRegistryEthSepolia.acceptAdminRole(address(rwaTokenEthSepolia));
        vm.stopPrank();

        // Step 14) Accept Admin role on Avalanche Fuji
        vm.selectFork(avalancheFujiFork);

        TokenAdminRegistry tokenAdminRegistryAvalancheFuji =
            TokenAdminRegistry(avalancheFujiNetworkDetails.tokenAdminRegistryAddress);

        vm.startPrank(alice);
        tokenAdminRegistryAvalancheFuji.acceptAdminRole(address(rwaTokenAvalancheFuji));
        vm.stopPrank();
 
        // Step 15) Accept Admin role on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);

        TokenAdminRegistry tokenAdminRegistryArbitrumSepolia =
            TokenAdminRegistry(arbitrumSepoliaNetworkDetails.tokenAdminRegistryAddress);

        vm.startPrank(alice);
        tokenAdminRegistryArbitrumSepolia.acceptAdminRole(address(rwaTokenArbitrumSepolia));
        vm.stopPrank();
 
        // Step 16) Link token to pool on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);

        vm.startPrank(alice);
        tokenAdminRegistryEthSepolia.setPool(address(rwaTokenEthSepolia), address(burnMintTokenPoolEthSepolia));
        vm.stopPrank();

        // Step 17) Link token to pool on Avalanche Fuji
        vm.selectFork(avalancheFujiFork);

        vm.startPrank(alice);
        tokenAdminRegistryAvalancheFuji.setPool(
            address(rwaTokenAvalancheFuji), address(burnMintTokenPoolAvalancheFuji)
        );
        vm.stopPrank();

        // Step 18) Link token to pool on Arbitrum Sepolia
        vm.selectFork(arbitrumSepoliaFork);

        vm.startPrank(alice);
        tokenAdminRegistryArbitrumSepolia.setPool(
            address(rwaTokenArbitrumSepolia), address(burnMintTokenPoolArbitrumSepolia)
        );
        vm.stopPrank();

        // Step 19) Configure Token Pool on Ethereum Sepolia (connect to Avalanche Fuji and Arbitrum Sepolia)
        vm.selectFork(ethSepoliaFork);

        vm.startPrank(alice);
        TokenPool.ChainUpdate[] memory chainsEthSepolia = new TokenPool.ChainUpdate[](2);
        
        // Connection to Avalanche Fuji
        bytes[] memory remotePoolAddressesAvalanche = new bytes[](1);
        remotePoolAddressesAvalanche[0] = abi.encode(address(burnMintTokenPoolAvalancheFuji));
        chainsEthSepolia[0] = TokenPool.ChainUpdate({
            remoteChainSelector: avalancheFujiNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddressesAvalanche,
            remoteTokenAddress: abi.encode(address(rwaTokenAvalancheFuji)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167})
        });

        // Connection to Arbitrum Sepolia
        bytes[] memory remotePoolAddressesArbitrum = new bytes[](1);
        remotePoolAddressesArbitrum[0] = abi.encode(address(burnMintTokenPoolArbitrumSepolia));
        chainsEthSepolia[1] = TokenPool.ChainUpdate({
            remoteChainSelector: arbitrumSepoliaNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddressesArbitrum,
            remoteTokenAddress: abi.encode(address(rwaTokenArbitrumSepolia)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167})
        });

        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        burnMintTokenPoolEthSepolia.applyChainUpdates(remoteChainSelectorsToRemove, chainsEthSepolia);
        vm.stopPrank();
  
        // Step 20) Configure Token Pool on Arbitrum Sepolia (connect to Ethereum Sepolia and Avalanche Fuji)
        vm.selectFork(arbitrumSepoliaFork);

        vm.startPrank(alice);
        TokenPool.ChainUpdate[] memory chainsArbitrum = new TokenPool.ChainUpdate[](2);
        
        // Connection to Ethereum Sepolia
        bytes[] memory remotePoolAddressesEthSepoliaFromArbitrum = new bytes[](1);
        remotePoolAddressesEthSepoliaFromArbitrum[0] = abi.encode(address(burnMintTokenPoolEthSepolia));
        chainsArbitrum[0] = TokenPool.ChainUpdate({
            remoteChainSelector: ethSepoliaNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddressesEthSepoliaFromArbitrum,
            remoteTokenAddress: abi.encode(address(rwaTokenEthSepolia)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167})
        });

        // Connection to Avalanche Fuji
        bytes[] memory remotePoolAddressesAvalancheFromArbitrum = new bytes[](1);
        remotePoolAddressesAvalancheFromArbitrum[0] = abi.encode(address(burnMintTokenPoolAvalancheFuji));
        chainsArbitrum[1] = TokenPool.ChainUpdate({
            remoteChainSelector: avalancheFujiNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddressesAvalancheFromArbitrum,
            remoteTokenAddress: abi.encode(address(rwaTokenAvalancheFuji)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: true, capacity: 100_000, rate: 167})
        });

        burnMintTokenPoolArbitrumSepolia.applyChainUpdates(remoteChainSelectorsToRemove, chainsArbitrum);
        vm.stopPrank();
 
        // Step 21) Test transfer from Ethereum Sepolia to Arbitrum Sepolia
        vm.selectFork(ethSepoliaFork);

        address linkSepolia = ethSepoliaNetworkDetails.linkAddress;
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(alice), 20 ether);

        uint256 amountToSend = 100;
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(rwaTokenEthSepolia), amount: amountToSend});
        tokenToSendDetails[0] = tokenAmount;

        vm.startPrank(alice);
        rwaTokenEthSepolia.mint(address(alice), amountToSend);

        rwaTokenEthSepolia.approve(ethSepoliaNetworkDetails.routerAddress, amountToSend);
        IERC20(linkSepolia).approve(ethSepoliaNetworkDetails.routerAddress, 20 ether);

        uint256 balanceOfAliceBeforeEthSepolia = rwaTokenEthSepolia.balanceOf(alice);

        IRouterClient routerEthSepolia = IRouterClient(ethSepoliaNetworkDetails.routerAddress);
        routerEthSepolia.ccipSend(
            arbitrumSepoliaNetworkDetails.chainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(address(alice)),
                data: "",
                tokenAmounts: tokenToSendDetails,
                extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
                feeToken: linkSepolia
            })
        );

        uint256 balanceOfAliceAfterEthSepolia = rwaTokenEthSepolia.balanceOf(alice);
        vm.stopPrank();

        assertEq(balanceOfAliceAfterEthSepolia, balanceOfAliceBeforeEthSepolia - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbitrumSepoliaFork);

        uint256 balanceOfAliceAfterArbitrumSepolia = rwaTokenArbitrumSepolia.balanceOf(alice);
        assertEq(balanceOfAliceAfterArbitrumSepolia, amountToSend);
 
        console.log("Multi-chain RWA token transfers completed successfully!");
        console.log("Ethereum Sepolia -> Arbitrum Sepolia: 100 tokens"); 
    }
}
