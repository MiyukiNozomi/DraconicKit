<script>
  import TestComponent from "$lib/testComponent.svelte";
</script>

<svelte:head>
  <title>Draconic Web Server!</title>
</svelte:head>

<h1>Draconic Web Server!</h1>
<p>An HTTP 1.1 implementation for haxe</p>

<p>Supports chunked transfers too! look at that image:</p>
<img src="/test.webp" alt="" />

<p>Edit src/routes/+page.svelte to edit this file.</p>

<p>I can also change it while the server is running too</p>

<p>Take this!</p>

<p class="thing">dayumn bro that's some crazy stuff..</p>

<TestComponent />

<style>
  p.thing {
    color: #fafafa;
    font-size: 12px;
  }
  body {
    background-color: black;
    color: white;
  }
  h1 {
    color: red;
  }
  p {
    color: #fafafa;
  }
</style>
