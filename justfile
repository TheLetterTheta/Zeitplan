set dotenv-load

build-web:
    rm web/dist/* || true
    cd web && elm-spa gen
    cd web && yarn parcel build public/index.html
    cd web/dist && sed -i 's/\/\//\//g' index.html
    cd web/dist && zip dist-deploy.zip ./*
    mv web/dist/dist-deploy.zip infrastructure/dist/
    
build-lambdas:
    just infrastructure/build
