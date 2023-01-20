set dotenv-load

build-web:
    rm -r web/dist
    cd web && npm run build
    
build-lambdas:
    just infrastructure/build

run-web:
    cd web && npm run dev