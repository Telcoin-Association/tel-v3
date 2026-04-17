**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [incorrect-equality](#incorrect-equality) (2 results) (Medium)
 - [reentrancy-events](#reentrancy-events) (2 results) (Low)
 - [timestamp](#timestamp) (2 results) (Low)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [naming-convention](#naming-convention) (21 results) (Informational)
## incorrect-equality
Impact: Medium
Confidence: High
 - [ ] ID-0
[TokenMigration.recoverERC20(address,address,uint256)](.src/TokenMigration.sol#L109-L122) uses a dangerous strict equality:
	- [balance == 0 || amount == 0 || amount > balance](.src/TokenMigration.sol#L117)

.src/TokenMigration.sol#L109-L122


 - [ ] ID-1
[TokenMigration.migrate()](.src/TokenMigration.sol#L73-L89) uses a dangerous strict equality:
	- [userBalance == 0](.src/TokenMigration.sol#L77)

.src/TokenMigration.sol#L73-L89


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-2
Reentrancy in [MintBurnWrapper.mint(address,uint256)](.src/MintBurnWrapper.sol#L70-L74):
	External calls:
	- [token.mint(_to,_amount)](.src/MintBurnWrapper.sol#L71)
	Event emitted after the call(s):
	- [BridgeMinted(msg.sender,_to,_amount)](.src/MintBurnWrapper.sol#L72)

.src/MintBurnWrapper.sol#L70-L74


 - [ ] ID-3
Reentrancy in [MintBurnWrapper.burn(address,uint256)](.src/MintBurnWrapper.sol#L82-L86):
	External calls:
	- [token.burn(_from,_amount)](.src/MintBurnWrapper.sol#L83)
	Event emitted after the call(s):
	- [BridgeBurned(msg.sender,_from,_amount)](.src/MintBurnWrapper.sol#L84)

.src/MintBurnWrapper.sol#L82-L86


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-4
[TokenMigration.setMigrationExpiry(uint256)](.src/TokenMigration.sol#L96-L100) uses timestamp for comparisons
	Dangerous comparisons:
	- [newMigrationExpiry == 0 || migrationExpiry > newMigrationExpiry](.src/TokenMigration.sol#L97)

.src/TokenMigration.sol#L96-L100


 - [ ] ID-5
[TokenMigration.migrate()](.src/TokenMigration.sol#L73-L89) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp >= migrationExpiry](.src/TokenMigration.sol#L74)

.src/TokenMigration.sol#L73-L89


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-6
solc-0.4.18 is an outdated solc version. Use a more recent version (at least 0.8.0), if possible.

## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-7
Parameter [NativeBridge.rescueTokens(address,uint256,address)._amount](.src/NativeBridge.sol#L93) is not in mixedCase

.src/NativeBridge.sol#L93


 - [ ] ID-8
Parameter [MintBurnWrapper.revokeBridge(address)._bridge](.src/MintBurnWrapper.sol#L108) is not in mixedCase

.src/MintBurnWrapper.sol#L108


 - [ ] ID-9
Parameter [MintBurnWrapper.authorizeBridge(address)._bridge](.src/MintBurnWrapper.sol#L95) is not in mixedCase

.src/MintBurnWrapper.sol#L95


 - [ ] ID-10
Parameter [TelcoinV3.rescueTokens(address,uint256,address)._token](.src/TelcoinV3.sol#L85) is not in mixedCase

.src/TelcoinV3.sol#L85


 - [ ] ID-11
Parameter [NativeBridge.rescueTokens(address,uint256,address)._to](.src/NativeBridge.sol#L93) is not in mixedCase

.src/NativeBridge.sol#L93


 - [ ] ID-12
Parameter [TelcoinBridge.send(SendParam,MessagingFee,address)._fee](.src/TelcoinBridge.sol#L74) is not in mixedCase

.src/TelcoinBridge.sol#L74


 - [ ] ID-13
Parameter [NativeBridge.send(SendParam,MessagingFee,address)._refundAddress](.src/NativeBridge.sol#L70) is not in mixedCase

.src/NativeBridge.sol#L70


 - [ ] ID-14
Parameter [TelcoinBridge.rescueTokens(address,uint256,address)._amount](.src/TelcoinBridge.sol#L98) is not in mixedCase

.src/TelcoinBridge.sol#L98


 - [ ] ID-15
Parameter [MintBurnWrapper.mint(address,uint256)._amount](.src/MintBurnWrapper.sol#L70) is not in mixedCase

.src/MintBurnWrapper.sol#L70


 - [ ] ID-16
Parameter [NativeBridge.send(SendParam,MessagingFee,address)._fee](.src/NativeBridge.sol#L69) is not in mixedCase

.src/NativeBridge.sol#L69


 - [ ] ID-17
Parameter [MintBurnWrapper.burn(address,uint256)._amount](.src/MintBurnWrapper.sol#L82) is not in mixedCase

.src/MintBurnWrapper.sol#L82


 - [ ] ID-18
Parameter [NativeBridge.send(SendParam,MessagingFee,address)._sendParam](.src/NativeBridge.sol#L68) is not in mixedCase

.src/NativeBridge.sol#L68


 - [ ] ID-19
Parameter [TelcoinBridge.send(SendParam,MessagingFee,address)._refundAddress](.src/TelcoinBridge.sol#L75) is not in mixedCase

.src/TelcoinBridge.sol#L75


 - [ ] ID-20
Parameter [TelcoinBridge.send(SendParam,MessagingFee,address)._sendParam](.src/TelcoinBridge.sol#L73) is not in mixedCase

.src/TelcoinBridge.sol#L73


 - [ ] ID-21
Parameter [MintBurnWrapper.burn(address,uint256)._from](.src/MintBurnWrapper.sol#L82) is not in mixedCase

.src/MintBurnWrapper.sol#L82


 - [ ] ID-22
Parameter [NativeBridge.rescueTokens(address,uint256,address)._token](.src/NativeBridge.sol#L93) is not in mixedCase

.src/NativeBridge.sol#L93


 - [ ] ID-23
Parameter [MintBurnWrapper.mint(address,uint256)._to](.src/MintBurnWrapper.sol#L70) is not in mixedCase

.src/MintBurnWrapper.sol#L70


 - [ ] ID-24
Parameter [TelcoinV3.rescueTokens(address,uint256,address)._to](.src/TelcoinV3.sol#L85) is not in mixedCase

.src/TelcoinV3.sol#L85


 - [ ] ID-25
Parameter [TelcoinBridge.rescueTokens(address,uint256,address)._to](.src/TelcoinBridge.sol#L98) is not in mixedCase

.src/TelcoinBridge.sol#L98


 - [ ] ID-26
Parameter [TelcoinV3.rescueTokens(address,uint256,address)._amount](.src/TelcoinV3.sol#L85) is not in mixedCase

.src/TelcoinV3.sol#L85


 - [ ] ID-27
Parameter [TelcoinBridge.rescueTokens(address,uint256,address)._token](.src/TelcoinBridge.sol#L98) is not in mixedCase

.src/TelcoinBridge.sol#L98


