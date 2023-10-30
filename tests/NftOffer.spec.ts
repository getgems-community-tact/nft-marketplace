import { Blockchain, SandboxContract } from '@ton-community/sandbox';
import { toNano } from 'ton-core';
import { NftOffer } from '../wrappers/NftOffer';
import '@ton-community/test-utils';

describe('NftOffer', () => {
    let blockchain: Blockchain;
    let nftOffer: SandboxContract<NftOffer>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        nftOffer = blockchain.openContract(await NftOffer.fromInit());

        const deployer = await blockchain.treasury('deployer');

        const deployResult = await nftOffer.send(
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
            to: nftOffer.address,
            deploy: true,
            success: true,
        });
    });

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and nftOffer are ready to use
    });
});
