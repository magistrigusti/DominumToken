import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/AllodiumMinter.tact',
    options: {
        debug: true,
    },
};
