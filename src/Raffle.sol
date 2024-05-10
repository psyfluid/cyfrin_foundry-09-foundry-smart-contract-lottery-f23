// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle contract
 * @author Patrick Collins
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2Plus {
    enum RaffleState {
        Open,
        Calculated
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Mock private immutable i_vrfCoordinator_mock;
    IVRFCoordinatorV2Plus private immutable i_vrfCoordinator;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    error Raffle__NotEnoughETHSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator_mock = VRFCoordinatorV2Mock(vrfCoordinator);
        i_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.Open;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Raffle: insufficient funds to enter raffle");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHSent();
        }

        if (s_raffleState != RaffleState.Open) revert Raffle__RaffleNotOpen();
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is open
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = RaffleState.Open == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.Calculated;
        uint256 requestId = 0;
        if (block.chainid == 31337) {
            requestId = i_vrfCoordinator_mock.requestRandomWords(
                i_keyHash, uint64(i_subscriptionId), REQUEST_CONFIRMATIONS, i_callbackGasLimit, NUM_WORDS
            );
        } else {
            requestId = i_vrfCoordinator.requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                    keyHash: i_keyHash,
                    subId: i_subscriptionId,
                    requestConfirmations: REQUEST_CONFIRMATIONS,
                    callbackGasLimit: i_callbackGasLimit,
                    numWords: NUM_WORDS,
                    extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
                })
            );
        }

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256, /* requestId */ uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];

        s_recentWinner = winner;
        s_raffleState = RaffleState.Open;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);

        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) revert Raffle__TransferFailed();
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
