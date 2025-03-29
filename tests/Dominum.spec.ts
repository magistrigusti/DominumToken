import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano } from '@ton/core';
import { Dominum } from '../wrappers/Dominum';
import '@ton/test-utils';

describe('Dominum', () => {
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let dominum: SandboxContract<Dominum>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        dominum = blockchain.openContract(await Dominum.fromInit());

        deployer = await blockchain.treasury('deployer');

        const deployResult = await dominum.send(
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
            to: dominum.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and allodium are ready to use
    });
});
