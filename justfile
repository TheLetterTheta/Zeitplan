build-web:
    rm -r web/dist
    cd web && npm run build

run-web:
    cd web && npm run dev