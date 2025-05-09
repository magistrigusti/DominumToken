import {Address, beginCell, Cell, toNano} from "@ton/core"
import {Blockchain, BlockchainSnapshot, SandboxContract, TreasuryContract} from "@ton/sandbox"
import {ExtendedAllodiumWallet} from "../wrappers/AllodiumWallet"
import {ExtendedAllodiumMinter} from "../wrappers/AllodiumMinter"

import {
    JettonUpdateContent,
    CloseMinting,
    Mint,
    AllodiumMinter,
    TakeWalletBalance,
    storeTakeWalletBalance,
    minTonsForStorage,
} from '../build/Allodium/tact_AllodiumMinter'

import "@ton/test-utils"

// this test suite includes tests for the extended functionality
describe("Jetton Minter Extended", () => {
    let blockchain: Blockchain
    let jettonMinter: SandboxContract<ExtendedAllodiumMinter>
    let jettonWallet: SandboxContract<ExtendedAllodiumWallet>
    let deployer: SandboxContract<TreasuryContract>

    let _jwallet_code = new Cell()
    let _minter_code = new Cell()
    let notDeployer: SandboxContract<TreasuryContract>

    let userWallet: (address: Address) => Promise<SandboxContract<ExtendedAllodiumWallet>>
    let defaultContent: Cell
    let snapshot: BlockchainSnapshot

    beforeAll(async () => {
    blockchain = await Blockchain.create()
    deployer = await blockchain.treasury("deployer")
    notDeployer = await blockchain.treasury("notDeployer")

    defaultContent = beginCell().endCell()
    const msg: JettonUpdateContent = {
        $$type: "JettonUpdateContent",
        queryId: 0n,
        content: defaultContent,
    }

    jettonMinter = blockchain.openContract(
        await ExtendedAllodiumMinter.fromInit(0n, deployer.address, defaultContent)
    )

    const deployResult = await jettonMinter.send(
        deployer.getSender(),
        { value: toNano("0.1") },
        msg,
    )

    expect(deployResult.transactions).toHaveTransaction({
        from: deployer.address,
        to: jettonMinter.address,
        deploy: true,
        success: true,
    })

    const minterCode = jettonMinter.init?.code
    if (!minterCode) {
        throw new Error("JettonMinter init is not defined")
    }
    _minter_code = minterCode

    jettonWallet = blockchain.openContract(
        await ExtendedAllodiumWallet.fromInit(0n, deployer.address, jettonMinter.address)
    )

    const walletCode = jettonWallet.init?.code
    if (!walletCode) {
        throw new Error("JettonWallet init is not defined")
    }
    _jwallet_code = walletCode

    userWallet = async (address: Address) => {
        return blockchain.openContract(
            new ExtendedAllodiumWallet(await jettonMinter.getGetWalletAddress(address))
        )
    }

    snapshot = blockchain.snapshot()
})


    beforeEach(async () => {
        await blockchain.loadFrom(snapshot)
    })

    it("Can close minting", async () => {
        const closeMinting: CloseMinting = {
            $$type: "CloseMinting",
        }
        const unsuccessfulCloseMinting = await jettonMinter.send(
            notDeployer.getSender(),
            {value: toNano("0.1")},
            closeMinting,
        )
        expect(unsuccessfulCloseMinting.transactions).toHaveTransaction({
            from: notDeployer.address,
            to: jettonMinter.address,
            aborted: true,
            exitCode: AllodiumMinter.errors["Incorrect sender"],
        })
        expect((await jettonMinter.getGetJettonData()).mintable).toBeTruthy()

        const successfulCloseMinting = await jettonMinter.send(
            deployer.getSender(),
            {value: toNano("0.1")},
            closeMinting,
        )
        expect(successfulCloseMinting.transactions).toHaveTransaction({
            from: deployer.address,
            to: jettonMinter.address,
            success: true,
        })
        expect((await jettonMinter.getGetJettonData()).mintable).toBeFalsy()

        const mintMsg: Mint = {
            $$type: "Mint",
            queryId: 0n,
            receiver: deployer.address,
            tonAmount: toNano("0.1"),
            mintMessage: {
                $$type: "JettonTransferInternal",
                queryId: 0n,
                amount: toNano("0.1"),
                sender: deployer.address,
                responseDestination: deployer.address,
                forwardPayload: beginCell().storeUint(0, 1).endCell().asSlice(),
                forwardTonAmount: 0n,
            },
        }
        const mintTryAfterClose = await jettonMinter.send(
            deployer.getSender(),
            {value: toNano("0.1")},
            mintMsg,
        )
        expect(mintTryAfterClose.transactions).toHaveTransaction({
            from: deployer.address,
            to: jettonMinter.address,
            aborted: true,
            exitCode: AllodiumMinter.errors["Mint is closed"],
        })
    })

    it("should report correct balance", async () => {
        const jettonMintAmount = 100n
        await jettonMinter.sendMint(
            deployer.getSender(),
            deployer.address,
            jettonMintAmount,
            0n,
            toNano(1),
        )
        const deployerJettonWallet = await userWallet(deployer.address)
        const jettonBalance = await deployerJettonWallet.getJettonBalance()

        const provideResult = await deployerJettonWallet.sendProvideWalletBalance(
            deployer.getSender(),
            toNano(1),
            notDeployer.address,
            false,
        )

        const msg: TakeWalletBalance = {
            $$type: "TakeWalletBalance",
            balance: jettonBalance,
            verifyInfo: null,
        }

        expect(provideResult.transactions).toHaveTransaction({
            from: deployerJettonWallet.address,
            to: notDeployer.address,
            body: beginCell().store(storeTakeWalletBalance(msg)).endCell(),
        })
    })

    it("should report with correct verify info", async () => {
        const jettonMintAmount = 100n
        await jettonMinter.sendMint(
            deployer.getSender(),
            deployer.address,
            jettonMintAmount,
            0n,
            toNano(1),
        )
        const deployerJettonWallet = await userWallet(deployer.address)
        const jettonBalance = await deployerJettonWallet.getJettonBalance()

        const provideResult = await deployerJettonWallet.sendProvideWalletBalance(
            deployer.getSender(),
            toNano(1),
            notDeployer.address,
            true,
        )

        const msg: TakeWalletBalance = {
            $$type: "TakeWalletBalance",
            balance: jettonBalance,
            verifyInfo: {
                $$type: "VerifyInfo",
                owner: deployer.address,
                minter: jettonMinter.address,
                code: _jwallet_code,
            },
        }

        expect(provideResult.transactions).toHaveTransaction({
            from: deployerJettonWallet.address,
            to: notDeployer.address,
            body: beginCell().store(storeTakeWalletBalance(msg)).endCell(),
        })
    })

    it("should claim all tons from minter", async () => {
        await deployer.send({
            to: jettonMinter.address,
            value: toNano(0.5),
            bounce: false,
        })

        const minterBalance = (await blockchain.getContract(jettonMinter.address)).balance

        // external -> claim request -> claim take
        const claimTonMinterResult = await jettonMinter.sendClaimTon(
            deployer.getSender(),
            notDeployer.address,
            toNano(1),
        )

        const claimTxTotalFees = claimTonMinterResult.transactions[1]!.totalFees.coins

        const claimInMsg = claimTonMinterResult.transactions[0]!.outMessages.get(0)!

        if (claimInMsg.info.type !== "internal") {
            // fail with expect
            fail("Expected the message type to not be 'internal")
        }

        const claimInMsgValue = claimInMsg.info.value.coins

        const claimOutMsg = claimTonMinterResult.transactions[1]!.outMessages.get(0)!

        if (claimOutMsg.info.type !== "internal") {
            // fail with expect
            fail("Expected the message type to not be 'internal")
        }

        const claimOutMsgFwdFee = claimOutMsg.info.forwardFee

        const expectedOutValue =
            minterBalance +
            claimInMsgValue -
            claimTxTotalFees -
            minTonsForStorage -
            claimOutMsgFwdFee

        const minterBalanceAfter = (await blockchain.getContract(jettonMinter.address)).balance
        expect(minterBalanceAfter).toEqual(minTonsForStorage)

        expect(claimTonMinterResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: notDeployer.address,
            value: expectedOutValue,
            success: true,
        })
    })

    it("should claim all tons from wallet", async () => {
        // mint to deploy wallet with correct state init
        await jettonMinter.sendMint(deployer.getSender(), deployer.address, 1000n, 0n, toNano(1))
        const deployerJettonWallet = await userWallet(deployer.address)

        await deployer.send({
            to: deployerJettonWallet.address,
            value: toNano(5),
            bounce: false,
        })

        const walletBalance = (await blockchain.getContract(deployerJettonWallet.address)).balance

        // external -> claim request -> claim take
        const claimTonJettonWalletResult = await deployerJettonWallet.sendClaimTon(
            deployer.getSender(),
            notDeployer.address,
            toNano(1),
        )

        const claimTxTotalFees = claimTonJettonWalletResult.transactions[1]!.totalFees.coins

        const claimInMsg = claimTonJettonWalletResult.transactions[0]!.outMessages.get(0)!

        if (claimInMsg.info.type !== "internal") {
            fail("Expected the message type to not be 'internal")
        }

        const claimInMsgValue = claimInMsg.info.value.coins

        const claimOutMsg = claimTonJettonWalletResult.transactions[1]!.outMessages.get(0)!

        if (claimOutMsg.info.type !== "internal") {
            fail("Expected the message type to not be 'internal")
        }

        const claimOutMsgFwdFee = claimOutMsg.info.forwardFee

        const expectedOutValue =
            walletBalance +
            claimInMsgValue -
            claimTxTotalFees -
            minTonsForStorage -
            claimOutMsgFwdFee

        const jettonWalletBalanceAfter = (
            await blockchain.getContract(deployerJettonWallet.address)
        ).balance
        expect(jettonWalletBalanceAfter).toEqual(minTonsForStorage)

        expect(claimTonJettonWalletResult.transactions).toHaveTransaction({
            from: deployerJettonWallet.address,
            to: notDeployer.address,
            value: expectedOutValue,
            success: true,
        })
    })

    it("should bounce claim with low balance", async () => {
        const jwState = (await blockchain.getContract(jettonMinter.address)).account
        jwState.account!.storage.balance.coins = 1n
        await blockchain.setShardAccount(jettonMinter.address, jwState)

        const minterBalance = (await blockchain.getContract(jettonMinter.address)).balance

        const sendValue = toNano(0.009)
        expect(minterBalance + sendValue).toBeLessThan(minTonsForStorage)

        // external -> claim request -> bounce back
        const claimTonMinterResult = await jettonMinter.sendClaimTon(
            deployer.getSender(),
            notDeployer.address,
            sendValue,
        )

        expect(claimTonMinterResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: jettonMinter.address,
            success: false,
            // https://github.com/ton-blockchain/ton/blob/303e92b7750dc443ae6c282fb478d2114079d216/crypto/block/transaction.cpp#L2860
            actionResultCode: AllodiumMinter.errors["Not enough Toncoin"],
        })

        expect(claimTonMinterResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: deployer.address,
            inMessageBounced: true,
        })
    })
})
