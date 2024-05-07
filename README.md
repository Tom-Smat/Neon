**Staking Contract With fixed quantity of reward tokens at a specified interval**

**NeonPool**
The staking mechanism of the Token Staking Contract draws heavy inspiration from the design of the Synthetix Staking Contract. 
In the Synthetix model, a predetermined quantity of reward tokens is distributed at regular intervals. 
Participants who stake tokens in the contract receive a share of these reward tokens based on the proportion of their staked amount compared to the total quantity of staked tokens.

Suppose there is a Synthetix Staking Contract with the following parameters:

**Total quantity of staked tokens: 10,000 tokens**
Total reward tokens allocated for distribution: 1,000 tokens per week
Alice stakes 1,000 tokens
Bob stakes 2,000 tokens
Carol stakes 3,000 tokens
To calculate the rewards for each participant, we can follow these steps:

**Calculate Total Stake Proportions:**
Alice's stake proportion: 1,000 / 10,000 = 0.1 (10%)
Bob's stake proportion: 2,000 / 10,000 = 0.2 (20%)
Carol's stake proportion: 3,000 / 10,000 = 0.3 (30%)

**Allocate Rewards:**
Total rewards for the week: 1,000 tokens
Alice's reward: 0.1 * 1,000 = 100 tokens
Bob's reward: 0.2 * 1,000 = 200 tokens
Carol's reward: 0.3 * 1,000 = 300 tokens

So, in this example, Alice would receive 100 tokens, Bob would receive 200 tokens, and Carol would receive 300 tokens as rewards for the week based on their stake proportions.
