import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/AllodiumJetton.tact',
    options: {
        debug: true,
    },
};
