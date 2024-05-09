# Provably Random Raffle Contracts

## About

This code is to create a provably random smart contract lottery.

## What we want it to do?

1. Users can enter by paying for a ticket
   1. The ticket fees are going to go to the winner during the draw.
2. After X period of time the lottery will automatically draw a winner.
   1. And this will be done programmatically.
3. Using Chainlink VRF & Chainlink Automation
   1. Chainlink VRF -> Randomness
   2. Chainlink Automation -> Time based trigger

## Tests

1. Write some deploy scripts
2. Write our tests
   1. Work on a local chain
   2. Forked Testnet
   3. Forked Mainnet

## Fund Subscription with LINK

```bash
forge script script/Interactions.s.sol:FundSubscription --rpc-url $SEPOLIA_RPC_URL --broadcast --account sepolia1

cast call 0xc1b748c175d7f7D80e26E097A08274766Ed3247C "getRecentWinner()" —-rpc-url $SEPOLIA_RPC_URL

forge test --debug testRaffleRecordsPlayerWhenTheyEnter
```
