// What kind of store this app is. One of three, chosen once per app:
//
//   instant  Food and grocery: a rider brings it within hours.
//   parcel   Shopping (clothes, shoes, electronics, beauty): a courier brings it in days.
//   heavy    Heavy items (furniture, appliances): a truck, booked for a slot.
//
// This is the ONLY file that differs between the three apps. The add-product page, its
// "what is missing" check, new-category defaults and the starter catalogue all read from here,
// so a food shop is never asked for a parcel size and a furniture shop is never asked for a
// "ready in 25 minutes".
//
// To switch an app to another kind, change STORE_KIND below (and run that kind's starter seeder).

export const STORE_KIND = 'instant';

const FOOD_SPECS = [{ title: 'Food details', labels: ['Ingredients', 'Shelf life', 'Storage', 'FSSAI licence no.'] }];
const PARCEL_SPECS = [{ title: 'General', labels: ['Material', 'Care', 'In the box'] }];
const HEAVY_SPECS = [
  { title: 'Build', labels: ['Material', 'Finish', 'Assembly', 'Warranty'] },
];

export const STORE_KINDS = {
  instant: {
    id: 'instant',
    // The quick starts offered when a category's sizes and colours are set up (see VariantSetupEditor).
    setupPresets: ['packs', 'portion', 'drinks', 'multipack'],
    profile: 'instant',
    name: 'Food & grocery',
    // Show the veg / non-veg mark. Prepared food must carry it; for packed grocery it is optional.
    diet: true,
    defaultStock: '20',
    defaultVehicle: false,
    // Food and grocery come in portions and pack sizes, not colours.
    colours: false,
    sizeLabel: 'Pack size',
    quickSizes: ['250 g', '500 g', '1 kg'],
    sizePlaceholder: 'e.g. 500 g',
    optionsTitle: 'It comes in more than one pack size',
    optionsOff: 'Leave off for one size; you only enter how many you have.',
    optionsOn: 'Give each pack size its own stock, and a price only if it differs.',
    stockLabel: 'How many are available today?',
    stockHint: 'Enter 0 to show it as sold out.',
    nameHint: 'e.g. Paneer Butter Masala',
    descriptionHint: 'What it is, what is in it, how it is served.',
    // Portion and add-on choices are the heart of a dish: show them up front, not under "More options".
    choicesFirst: true,
    // Maker and packer details only matter for packaged goods, so fold them away.
    manufacturerFolded: true,
    manufacturerHint: 'Packaged goods must show who made and packed them. Skip this for dishes you cook.',
    specStarter: FOOD_SPECS,
    delivery: {
      title: 'Preparation & delivery',
      intro: 'A local rider brings it within hours. Say how long it takes to get ready, so the rider is sent at the right time.',
      stepHint: 'How long it takes to get ready',
      prep: true,
      weight: 'optional',
      weightHint: 'Only for packed goods. 1 kg is 1000.',
      dimensions: false,
      vehicle: false,
    },
    needs: { weight: false, dimensions: false },
  },

  parcel: {
    id: 'parcel',
    // The quick starts offered when a category's sizes and colours are set up (see VariantSetupEditor).
    setupPresets: ['clothes', 'shoes', 'kids', 'phones'],
    profile: 'parcel',
    name: 'Shopping',
    diet: false,
    defaultStock: '10',
    defaultVehicle: false,
    colours: true,
    sizeLabel: 'Size',
    quickSizes: ['S', 'M', 'L', 'XL', 'XXL'],
    sizePlaceholder: 'e.g. M',
    optionsTitle: 'It comes in sizes or colours',
    optionsOff: 'Leave off for a single item; you only enter how many you have.',
    optionsOn: 'Give each one its own stock, and a price only if it differs.',
    stockLabel: 'How many do you have?',
    stockHint: '',
    nameHint: 'e.g. Chanderi Silk Anarkali Set',
    descriptionHint: 'Material, size, how it is used, how to care for it. Shoppers read this on the product page.',
    choicesFirst: false,
    manufacturerFolded: false,
    manufacturerHint: 'Packaged goods sold in India must show who made and packed them. Leave out what does not apply.',
    specStarter: PARCEL_SPECS,
    delivery: {
      title: 'Delivery',
      intro: 'Couriers charge by weight and size. Without a weight the shop assumes a default, which can make delivery prices wrong.',
      stepHint: 'Weight and size of the parcel',
      prep: false,
      weight: 'suggested',
      weightHint: '1 kg is 1000.',
      dimensions: true,
      vehicle: true,
    },
    needs: { weight: false, dimensions: false },
  },

  heavy: {
    id: 'heavy',
    // The quick starts offered when a category's sizes and colours are set up (see VariantSetupEditor).
    setupPresets: ['sofas', 'beds', 'storage', 'laundry', 'cooling'],
    profile: 'heavy',
    name: 'Heavy items',
    diet: false,
    defaultStock: '5',
    defaultVehicle: true,
    colours: true,
    sizeLabel: 'Size',
    quickSizes: [],
    sizePlaceholder: 'e.g. 3-seater',
    colourLabel: 'Finish or colour',
    colourPlaceholder: 'e.g. Walnut',
    optionsTitle: 'It comes in different sizes or finishes',
    optionsOff: 'Leave off for a single item; you only enter how many you have.',
    optionsOn: 'Give each size or finish its own stock, and a price only if it differs.',
    stockLabel: 'How many are in stock?',
    stockHint: '',
    nameHint: 'e.g. 3-Seater Fabric Sofa',
    descriptionHint: 'Material, size, what is in the box, whether it needs assembling.',
    choicesFirst: false,
    manufacturerFolded: true,
    manufacturerHint: 'Optional. Add who made it if you want it on the product page.',
    specStarter: HEAVY_SPECS,
    delivery: {
      title: 'Weight, size & delivery',
      intro: 'A truck is booked for a slot, so the packed weight and size must be right. The default parcel size would book the wrong vehicle.',
      stepHint: 'Packed weight and size, for the truck',
      prep: false,
      weight: 'required',
      weightHint: 'Packed weight. 1 kg is 1000.',
      dimensions: true,
      vehicle: true,
    },
    needs: { weight: true, dimensions: true },
  },
};

export const currentKind = STORE_KINDS[STORE_KIND] || STORE_KINDS.parcel;

/** The delivery type a new category starts with in this app. */
export const defaultProfile = currentKind.profile;
