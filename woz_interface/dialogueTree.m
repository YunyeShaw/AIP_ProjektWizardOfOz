function T = dialogueTree()
%DIALOGUETREE Restaurant-ordering dialogue tree (from restaurant_ordering_branching_dialogue.drawio).
%
%   T.clips  : map clipID -> waiter text (each clip = one prerecorded WAV: audio/<clipID>.wav)
%   T.states : struct of decision points. Each state has
%                .title    shown to the wizard
%                .intents  struct array with fields
%                          label  - button text (customer intent)
%                          play   - cellstr of waiter clip IDs to play (in order)
%                          next   - next state name
%                          set    - optional {'dish','pasta'} / {'drink','tea'} slot assignment
%   Special clip ID '$CONFIRM' is resolved at runtime to C_<dish>_<drink>.
%   Edit this file to change the dialogue; the GUI rebuilds itself from it.

dishes = {'salmon','pasta','chicken_salad'};
dishTxt = {'grilled salmon','pasta','chicken salad'};
drinks = {'water','lemonade','tea','none'};
drinkTxt = {'water','lemonade','ginger tea','no drink'};

c = containers.Map();
c('W01_ready')     = 'Are you ready to order?';
c('W02_comeback')  = 'Of course. I''ll come back in a few minutes.';
c('W03_drinks')    = 'We have water, lemonade and ginger tea.';
c('W04_dishes')    = 'Certainly. We have grilled salmon, pasta and chicken salad today.';
c('W05_great')     = 'Great! What would you like to order?';
c('W06_special')   = 'Today''s special is grilled salmon with rice.';
c('W07_discount')  = 'Yes, our pasta is discounted today.';
c('W08_recommend') = 'I recommend our chicken salad.';
c('W09_follow')    = 'Would you like to order that, or something else?';
c('W10_askdrink')  = 'Would you like anything to drink? We have water, lemonade and ginger tea.';
c('W11_perfect')   = 'Perfect. I''ll bring your order shortly.';
c('W12_instead')   = 'Of course. What would you like instead?';
c('W13_noproblem') = 'No problem. Let me know if you need anything.';
c('W14_taketime')  = 'Please take your time.';
c('W99_fallback')  = 'Sorry, could you choose from our menu?';
for i = 1:numel(dishes)
    for j = 1:numel(drinks)
        if strcmp(drinks{j},'none')
            txt = sprintf('So that''s %s and no drink. Is that correct?', dishTxt{i});
        else
            txt = sprintf('So that''s %s and %s. Is that correct?', dishTxt{i}, drinkTxt{j});
        end
        c(sprintf('C_%s_%s', dishes{i}, drinks{j})) = txt;
    end
end
T.clips = c;

I = @(label, play, next, varargin) struct('label',label,'play',{play},'next',next,'set',{varargin});
orderDish = @(k) I(['Order ' dishTxt{k}], {'W10_askdrink'}, 'DRINK', 'dish', dishes{k});

S = struct();

% ---------- Page 1 ----------
S.READY.title = 'Waiter asked: "Are you ready to order?"';
S.READY.intents = [ ...
    I('Yes',            {'W05_great'},               'ORDER'), ...
    I('Not yet',        {'W02_comeback'},            'WAITING'), ...
    I('See menu',       {'W03_drinks','W04_dishes'}, 'MENU_SHOWN')];

S.MENU_SHOWN.title = 'Waiter listed the menu (drinks + dishes) - customer is browsing';
S.MENU_SHOWN.intents = [ ...
    I('Ready to order', {'W05_great'},               'ORDER'), ...
    I('Not yet',        {'W02_comeback'},            'WAITING'), ...
    I('Repeat menu',    {'W03_drinks','W04_dishes'}, 'MENU_SHOWN')];

S.WAITING.title = 'Waiter left - come back later';
S.WAITING.intents = I('Waiter returns', {'W01_ready'}, 'READY');

S.ORDER.title = 'Waiter asked: "What would you like to order?"';
S.ORDER.intents = [ ...
    I('Ask about special',   {'W06_special','W09_follow'},  'FOLLOW', 'dish', 'salmon'), ...
    I('Ask about discounts', {'W07_discount','W09_follow'}, 'FOLLOW', 'dish', 'pasta'), ...
    I('Ask recommendation',  {'W08_recommend','W09_follow'},   'FOLLOW', 'dish', 'chicken_salad'), ...
    orderDish(1), orderDish(2), orderDish(3), ...
    I('Irrelevant answer',   {'W14_taketime'}, 'ORDER')];

S.FOLLOW.title = 'Waiter asked: "Order that, or something else?"';
S.FOLLOW.intents = [ ...
    I('Yes, that one', {'W10_askdrink'}, 'DRINK'), ...
    orderDish(1), orderDish(2), orderDish(3), ...
    I('Something else / ask again', {'W05_great'}, 'ORDER')];

% ---------- Page 2 ----------
S.DRINK.title = 'Waiter asked: "Anything to drink?"';
S.DRINK.intents = [ ...
    I('Water',     {'$CONFIRM'}, 'CONFIRM', 'drink', 'water'), ...
    I('Lemonade',  {'$CONFIRM'}, 'CONFIRM', 'drink', 'lemonade'), ...
    I('Ginger tea',{'$CONFIRM'}, 'CONFIRM', 'drink', 'tea'), ...
    I('No drink',  {'$CONFIRM'}, 'CONFIRM', 'drink', 'none'), ...
    I('What drinks do you have?', {'W03_drinks'}, 'DRINK')];

S.CONFIRM.title = 'Waiter asked: "So that''s [dish] and [drink]. Correct?"';
S.CONFIRM.intents = [ ...
    I('Yes, correct',  {'W11_perfect'},   'END_OK'), ...
    I('Change order',  {'W12_instead'},   'ORDER'), ...
    I('Cancel',        {'W13_noproblem'}, 'END_NO')];

S.END_OK.title = 'END: Order placed';
S.END_OK.intents = I('Start over', {'W01_ready'}, 'READY');
S.END_NO.title = 'END: No order';
S.END_NO.intents = I('Start over', {'W01_ready'}, 'READY');

T.states = S;
T.start = 'READY';
T.startClips = {'W01_ready'};
T.fallbackClip = 'W99_fallback';
end
