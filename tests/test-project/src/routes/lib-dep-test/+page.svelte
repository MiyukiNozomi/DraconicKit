<script lang="ts">
  import { getSomethingFromHere } from "$lib";
  import { onMount } from "svelte";

  let value = $state();

  onMount(() => {
    console.log((value = getSomethingFromHere()));
  });
</script>

<h2 style="color: #ff0000;">Check logs!</h2>
<p style="color: #f0f0f0">Lies, check this: {JSON.stringify(value)}</p>
