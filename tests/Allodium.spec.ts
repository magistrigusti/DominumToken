import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano } from '@ton/core';
import { Allodium } from '../wrappers/Allodium';
import '@ton/test-utils';

describe('Allodium', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let allodium: SandboxContract<Allodium>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        allodium = blockchain.openContract(await Allodium.fromInit());

        deployer = await blockchain.treasury('deployer');

        const deployResult = await allodium.send(
            deployer.getSender(),
            {
                value: toNano('0.05'),
            },
            {
                $$type: 'Deploy',
                queryId: 0n,
            }
        );

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: allodium.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and allodium are ready to use
    });
});
