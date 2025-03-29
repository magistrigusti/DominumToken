import { toNano } from '@ton/core';
import { Dominum } from '../wrappers/Dominum';
import { NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const dominum = provider.open(await Dominum.fromInit());

    await dominum.send(
        provider.sender(),
        {
            value: toNano('0.05'),
        },
        {
            $$type: 'Deploy',
            queryId: 0n,
        }
    );

    await provider.waitForDeploy(dominum.address);

    // run methods on `dominum`
}
