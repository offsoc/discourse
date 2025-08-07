import { array } from "@ember/helper";
import { LinkTo } from "@ember/routing";
import ReviewableTags from "discourse/components/reviewable-tags";
import TopicStatus from "discourse/components/topic-status";
import categoryBadge from "discourse/helpers/category-badge";
import highlightWatchedWords from "discourse/lib/highlight-watched-words";
import { i18n } from "discourse-i18n";

/**
 * Displays topic information for reviewable items.
 * Shows the topic title, status, category badge, and tags if the topic exists.
 * For deleted topics, displays a link to the original topic. Supports block content as fallback.
 *
 * @component ReviewableTopicLink
 *
 * @example
 * ```gjs
 * <ReviewableTopicLink @reviewable={{this.reviewable}} />
 *
 * <!-- With block content for custom fallback -->
 * <ReviewableTopicLink @reviewable={{this.reviewable}}>
 *   <span>Custom content when topic is missing</span>
 * </ReviewableTopicLink>
 * ```
 *
 * @param {Reviewable} reviewable - The reviewable object containing topic information
 */
<template>
  <div class="post-topic">
    {{#if @reviewable.topic}}
      <TopicStatus
        @topic={{@reviewable.topic}}
        @showPrivateMessageIcon={{true}}
      />

      <a
        href={{@reviewable.target_url}}
        class="title-text"
      >{{highlightWatchedWords @reviewable.topic.fancyTitle @reviewable}}</a>

      {{categoryBadge @reviewable.category}}

      <ReviewableTags @tags={{@reviewable.topic_tags}} @tagName="" />
    {{else if (has-block)}}
      {{yield}}
    {{else}}
      <span class="title-text">
        {{i18n "review.topics.deleted"}}
        <LinkTo
          @route="topic"
          @models={{array "-" @reviewable.removed_topic_id}}
        >{{i18n "review.topics.original"}}</LinkTo>
      </span>
    {{/if}}
  </div>
</template>
