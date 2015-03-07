# Discourse-Webhooks
Add the ability to make HTTP requests from Discourse in response to certain events.

# How To Use

1. See: [How to install Discourse plugins](https://meta.discourse.org/t/install-a-plugin/19157)

2. Create a route on your site for handling POST requests with JSON data. You should accept the event names as part of the URL, or in a query string.

  * Events are triggered with variable amounts of parameters, with no real definition of what event gets what parameters. The JSON data will contain an array of the parameters, in the order they were given.
  * If you choose to include the API key as part of the request, it will always be in the first value.

3. In the Discourse admin settings, under the "Webhooks" section, modify the "webhooks url format" to point at the route from step 2.

4. If you need to change the list of events that are registered, you'll need to restart Discourse to pick up those changes. There's currently no way to unregister events at run-time, and no way to determine which events were already registered by this plugin.

5. There are no formal event definitions. To get a list of possible events, check the [Discourse source code](https://github.com/discourse/discourse/search?q=DiscourseEvent.trigger+path%3A%2Flib+path%3A%2Fapp&type=Code)

6. Make sure to check the "webhooks enabled" box to start sending HTTP requests for events.
