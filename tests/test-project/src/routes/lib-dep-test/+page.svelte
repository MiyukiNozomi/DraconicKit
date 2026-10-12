<script>
  import { getSomethingFromHere } from "$lib/index.js";
  import { onMount } from "svelte";

  onMount(() => {
    console.log(getSomethingFromHere());
  });
</script>

<h2 style="color: #ff0000;">Check logs!</h2>
