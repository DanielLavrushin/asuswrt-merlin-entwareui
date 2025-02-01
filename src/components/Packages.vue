<template>
    <table class="FormTable" style="width: 100%">
        <thead>
            <tr>
                <td colspan="3">
                    Installed Packages
                </td>
            </tr>
        </thead>
        <tbody>
            <tr v-for="pkg in packages" :key="pkg.name">
                <td>
                    {{ pkg.name }}
                </td>
                <td>
                    {{ pkg.version }}
                </td>
                <td>
                    <span class="row-buttons">
                        <a class="button_gen button_gen_small" href="#">info</a>
                        <a class="button_gen button_gen_small" href="#">dependencies</a>
                        <a class="button_gen button_gen_small" href="#">uninstall</a>

                    </span>
                </td>
            </tr>
        </tbody>
    </table>

</template>

<script lang="ts">
import { defineComponent, ref, onMounted } from "vue";
import engine, { EntwareAction, EntwarePackage } from "../modules/Engine";

export default defineComponent({
    name: "Packages",
    setup() {
        const packages = ref<EntwarePackage[]>([]);

        const fetchPackages = async () => {
            await engine.executeWithLoadingProgress(async () => {
                await engine.submit(EntwareAction.INSTALLED_PACKAGES);
                const result = await engine.getResponse();
                packages.value = result.entware?.installed || [];
            }, false);
        };

        onMounted(() => {
            fetchPackages();
        });
        return { packages };
    },
});

</script>
<style scoped>
.FormTable tr:hover td {
    font-weight: bold;
    text-shadow: 1px 1px 2px #fc0;
}
</style>