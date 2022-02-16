# proxy-depositor
> the real meat of this comes from the proxy depositor, existing versions like cvx are needlessly complex and have features we do not need
> proxy depositor I believe should truly be a proxy, or potentially a diamond if time allows for adding functionality, needs to be modular and allow for multi rewards and other things that gauges can do. especially with bribes coming
> proxy depositor basically becomes its own MasterChef for whitelisted depositors, essentially passing back rewards and keeping track of tokens passing through it
> i think existing wrapper tokens have the problem where they need to be outside the LP token in order to receive allotted rewards, we should be able to remove that from the equation by either allowing for rewards to go to people staking BPT of the wrapped-token pairing or doing a baby boo style air drop or weekly rewards

## Notes
Rewards are received by calling mint() on the TokenMinter with the address of the targeted gauge
This will distribute all the rewards the proxy-depositor is entitled to for this gauge.
Now the depositor needs to relay said rewards to the strategy and the voters
This may be achieved in a number of ways, including :
* Gettting accurate information on what % of the rewards is due to the boost, what is the base APR, and splitting according to that
* Find another way lol

## Registry

### HND
0x10010078a54396F62c96dF8532dc2B4847d47ED3

### hUSDC
0x243e33aa7f6787154a8e59d3c27a66db3f8818ee

### hUSDC gauge deposit
0x110614276F7b9Ae8586a1C1D9Bc079771e2CE8cF

### veHND
0x376020c5B0ba3Fd603d7722381fAA06DA8078d8a

### Gauge Controller
0xb1c4426C86082D91a6c097fC588E5D5d8dD1f5a8

### Comptroller
0x0F390559F258eB8591C8e31Cf0905E97cf36ACE2

### Token Minter
0x42b458056f887fd665ed6f160a59afe932e1f559