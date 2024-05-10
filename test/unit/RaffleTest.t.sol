// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        _;
    }

    modifier raffleTimePassed() {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (entranceFee, interval, vrfCoordinator, keyHash, subscriptionId, callbackGasLimit, link,) =
            helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.Open);
    }

    ////////////////////////////////////////////////
    // enterRaffle
    ////////////////////////////////////////////////
    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughETHSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public raffleEntered {
        address playerRecorded = raffle.getPlayer(0);
        assertEq(playerRecorded, PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCanEnterWhenRaffleIsCalculating() public raffleEntered raffleTimePassed {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    //////////////////////////////////////////////
    // checkUpkeep
    //////////////////////////////////////////////
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public raffleTimePassed {
        // Arrange

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public raffleEntered raffleTimePassed {
        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public raffleEntered {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public raffleEntered raffleTimePassed {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    //////////////////////////////////////////////
    // performUpkeep
    //////////////////////////////////////////////
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEntered raffleTimePassed {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, 0, 0, 0));
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered raffleTimePassed {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        assert(uint256(requestId) > 0);
        assert(raffle.getRaffleState() == Raffle.RaffleState.Calculated);
    }

    //////////////////////////////////////////////
    // fulfillRandonWords
    //////////////////////////////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        skipFork
        raffleEntered
        raffleTimePassed
    {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendMoney() public skipFork raffleEntered raffleTimePassed {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assert(raffle.getRaffleState() == Raffle.RaffleState.Open);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getNumberOfPlayers() == 0);
        assert(raffle.getLastTimeStamp() > previousTimeStamp);
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE - entranceFee + prize);
    }
}
